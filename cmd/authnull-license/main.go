// Command authnull-license generates keypairs and signs on-premise licences.
//
// AUTHNULL-INTERNAL. The private key it produces is the only thing standing between a customer and a
// self-issued perpetual licence, so it never ships in the on-premise package and never goes in a
// container image.
//
//	# once, ever — keep the private key somewhere it can be found in three years
//	authnull-license keygen -out ./keys
//
//	# the public half is compiled into the on-premise build
//	go build -ldflags "-X github.com/authnull0/authnull-service/pkg/license.PublicKeyBase64=$(cat keys/license.pub)" ./cmd/authnull-service
//
//	# per customer
//	authnull-license sign -key keys/license.key -customer "Acme Ltd" -days 365 -features ad -out acme.lic
//
//	# what a customer will see, without installing it
//	authnull-license show -pub keys/license.pub -in acme.lic
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/authnull0/authnull-service/pkg/license"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "keygen":
		err = keygen(os.Args[2:])
	case "sign":
		err = sign(os.Args[2:])
	case "show":
		err = show(os.Args[2:])
	case "-h", "--help", "help":
		usage()
		return
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n", os.Args[1])
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `authnull-license — issue on-premise licences (Authnull internal)

  keygen -out DIR              generate the signing keypair (once, ever)
  sign   -key FILE -customer NAME -days N [-features ad,database,radius]
         [-tier NAME] [-id ID] [-out FILE]
  show   -pub FILE -in FILE    verify and print a licence

The private key must never ship in the on-premise package or a container image.
`)
}

func keygen(args []string) error {
	fs := flag.NewFlagSet("keygen", flag.ExitOnError)
	out := fs.String("out", ".", "directory to write license.key and license.pub into")
	if err := fs.Parse(args); err != nil {
		return err
	}

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return fmt.Errorf("generate key: %w", err)
	}
	if err := os.MkdirAll(*out, 0o700); err != nil {
		return err
	}

	keyPath := filepath.Join(*out, "license.key")
	pubPath := filepath.Join(*out, "license.pub")

	// Refuse to overwrite. Regenerating the private key invalidates every licence ever issued, and
	// there is no way to tell that has happened until customers start reporting failures.
	for _, p := range []string{keyPath, pubPath} {
		if _, err := os.Stat(p); err == nil {
			return fmt.Errorf("%s already exists — refusing to overwrite; regenerating the key "+
				"invalidates every licence already issued", p)
		}
	}

	// 0600: the private key is the whole security model.
	if err := os.WriteFile(keyPath, []byte(base64.StdEncoding.EncodeToString(priv)+"\n"), 0o600); err != nil {
		return err
	}
	if err := os.WriteFile(pubPath, []byte(base64.StdEncoding.EncodeToString(pub)+"\n"), 0o644); err != nil {
		return err
	}

	fmt.Printf("private key: %s  (keep safe, never ship)\n", keyPath)
	fmt.Printf("public key:  %s\n\n", pubPath)
	fmt.Printf("compile the public key into the on-premise build:\n")
	fmt.Printf("  go build -ldflags \"-X github.com/authnull0/authnull-service/pkg/license.PublicKeyBase64=%s\" ./cmd/authnull-service\n",
		base64.StdEncoding.EncodeToString(pub))
	return nil
}

func sign(args []string) error {
	fs := flag.NewFlagSet("sign", flag.ExitOnError)
	keyPath := fs.String("key", "", "path to license.key")
	customer := fs.String("customer", "", "customer name, shown in their console")
	days := fs.Int("days", 365, "validity in days from today")
	featureList := fs.String("features", license.FeatureAD, "comma-separated: ad,database,radius")
	tier := fs.String("tier", "standard", "tier label, for support and reporting only")
	id := fs.String("id", "", "licence id; a random one is generated when empty")
	out := fs.String("out", "", "output file; stdout when empty")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *keyPath == "" || strings.TrimSpace(*customer) == "" {
		return fmt.Errorf("-key and -customer are required")
	}
	if *days <= 0 {
		return fmt.Errorf("-days must be positive")
	}

	priv, err := readPrivateKey(*keyPath)
	if err != nil {
		return err
	}

	features, err := parseFeatures(*featureList)
	if err != nil {
		return err
	}

	licenceID := strings.TrimSpace(*id)
	if licenceID == "" {
		licenceID, err = randomHex(8)
		if err != nil {
			return err
		}
		licenceID = "lic-" + licenceID
	}
	nonce, err := randomHex(8)
	if err != nil {
		return err
	}

	// Truncated to the day, in UTC. A licence that expires at 14:37 is impossible to reason about in a
	// support conversation, and the extra precision buys nothing.
	now := time.Now().UTC().Truncate(24 * time.Hour)
	payload := license.Payload{
		ID:        licenceID,
		Customer:  strings.TrimSpace(*customer),
		IssuedAt:  now,
		ExpiresAt: now.AddDate(0, 0, *days),
		Tier:      strings.TrimSpace(*tier),
		Features:  features,
		Nonce:     nonce,
	}

	// license.Sign, not a local implementation: what gets signed must be decided in exactly one
	// place. Writing the document here with json.MarshalIndent re-indented the embedded payload and
	// produced licences that failed to verify against their own signature.
	doc, err := license.Sign(payload, priv)
	if err != nil {
		return err
	}

	if *out == "" {
		fmt.Print(string(doc))
	} else if err := os.WriteFile(*out, doc, 0o644); err != nil {
		return err
	}

	// To stderr so it does not contaminate the licence when writing to stdout.
	fmt.Fprintf(os.Stderr, "issued %s for %q: %s .. %s, features %s\n",
		payload.ID, payload.Customer,
		payload.IssuedAt.Format("2006-01-02"), payload.ExpiresAt.Format("2006-01-02"),
		strings.Join(payload.Features, ","))
	return nil
}

func show(args []string) error {
	fs := flag.NewFlagSet("show", flag.ExitOnError)
	pubPath := fs.String("pub", "", "path to license.pub")
	in := fs.String("in", "", "licence file to inspect")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *pubPath == "" || *in == "" {
		return fmt.Errorf("-pub and -in are required")
	}

	pubRaw, err := os.ReadFile(*pubPath)
	if err != nil {
		return err
	}
	pub, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(pubRaw)))
	if err != nil {
		return fmt.Errorf("public key is not base64: %w", err)
	}
	body, err := os.ReadFile(*in)
	if err != nil {
		return err
	}

	payload, err := license.Verify(body, ed25519.PublicKey(pub))
	if err != nil {
		return err
	}
	// Evaluated as the customer's deployment would, so "valid" here means valid there.
	st := license.Evaluate(payload, time.Time{}, time.Now())

	fmt.Printf("id:        %s\n", payload.ID)
	fmt.Printf("customer:  %s\n", payload.Customer)
	fmt.Printf("tier:      %s\n", payload.Tier)
	fmt.Printf("issued:    %s\n", payload.IssuedAt.Format("2006-01-02"))
	fmt.Printf("expires:   %s\n", payload.ExpiresAt.Format("2006-01-02"))
	fmt.Printf("features:  %s\n", strings.Join(payload.Features, ","))
	fmt.Printf("state:     %s (licensed=%v, %d days remaining)\n", st.State, st.Licensed, st.DaysRemaining)
	if st.Reason != "" {
		fmt.Printf("note:      %s\n", st.Reason)
	}
	return nil
}

func readPrivateKey(path string) (ed25519.PrivateKey, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(raw)))
	if err != nil {
		return nil, fmt.Errorf("private key is not base64: %w", err)
	}
	if len(decoded) != ed25519.PrivateKeySize {
		return nil, fmt.Errorf("private key is %d bytes, want %d", len(decoded), ed25519.PrivateKeySize)
	}
	return ed25519.PrivateKey(decoded), nil
}

// parseFeatures rejects unknown names rather than passing them through.
//
// A typo like "radiusx" would otherwise produce a licence that verifies perfectly and grants nothing,
// and the customer would be the one to discover it.
func parseFeatures(list string) ([]string, error) {
	known := map[string]bool{
		license.FeatureAD:       true,
		license.FeatureDatabase: true,
		license.FeatureRADIUS:   true,
	}
	var out []string
	for _, f := range strings.Split(list, ",") {
		f = strings.ToLower(strings.TrimSpace(f))
		if f == "" {
			continue
		}
		if !known[f] {
			return nil, fmt.Errorf("unknown feature %q (known: ad, database, radius)", f)
		}
		out = append(out, f)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("at least one feature is required — a licence granting nothing is not useful")
	}
	return out, nil
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
