-- The public halves of the three keys a proxy holds, so the console can show them.
--
-- WHY THE CONSOLE NEEDS THEM
--
-- Onboarding a jump server means putting three values somewhere else: the host key
-- fingerprint that operators are asked to trust, the backend public key that goes into a
-- target's authorized_keys, and the CA public key that goes into a target's
-- TrustedUserCAKeys. Today all three are printed by install-sshproxy.sh, once, on the jump
-- box -- so the onboarding wizard cannot show them, and an administrator who closed that
-- terminal has to SSH back in and cat a file.
--
-- A hand-retyped public key is a support ticket. The wizard needs a copy button, and a
-- copy button needs the value.
--
-- WHY THE PROXY REPORTS THEM RATHER THAN THE CONSOLE ASKING
--
-- Same reason as everything else on this channel: a jump box accepts no inbound connection
-- but SSH. The proxy already heartbeats outward every minute; these ride along on a
-- request that was being made anyway.
--
-- PUBLIC HALVES ONLY
--
-- Never the private key, and this is worth stating in the schema because the column names
-- are one careless change away from being wrong. The host key and the CA key are the two
-- most dangerous files on a jump box: the CA can mint a certificate for any account on any
-- host that trusts it, and the host key IS the proxy's identity. Their public halves are
-- safe to publish -- that is what public means, and both are pasted into world-readable
-- files on target machines as part of normal setup.
--
-- Nullable, all three. A proxy that has not reported yet, one built before this existed,
-- and one with no CA configured are all ordinary states; the wizard shows "waiting for the
-- proxy to report" rather than an empty code block that looks copyable.
--
-- WIDTHS
--
-- An ed25519 public key in authorized_keys form is ~80 characters and an RSA-4096 one is
-- ~740, plus a comment. 1024 holds either with room to spare, and is not a limit anybody
-- will discover in production. A SHA-256 fingerprint is 50 characters including the
-- `SHA256:` prefix; 128 leaves room for a format that is not this one.

ALTER TABLE did.jump_server
    ADD COLUMN IF NOT EXISTS host_key_fingerprint varchar(128)  NULL,
    ADD COLUMN IF NOT EXISTS backend_public_key   varchar(1024) NULL,
    ADD COLUMN IF NOT EXISTS ca_public_key        varchar(1024) NULL;
