package email

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"gopkg.in/gomail.v2"
)

// Send delivers an HTML email to the given recipient over SMTP. All transport
// settings are read from the environment so no credentials are compiled in:
//
//	SMTP_HOST     - SMTP server hostname
//	SMTP_PORT     - SMTP server port (integer)
//	SMTP_FROM     - sender address, also used as the auth username
//	SMTP_PASSWORD - auth credential
//	SMTP_BCC      - optional, comma-separated list of blind-copy recipients
func Send(to, subject, body string) error {
	host := os.Getenv("SMTP_HOST")
	from := os.Getenv("SMTP_FROM")
	password := os.Getenv("SMTP_PASSWORD")

	port, err := strconv.Atoi(os.Getenv("SMTP_PORT"))
	if err != nil {
		return fmt.Errorf("invalid SMTP_PORT: %w", err)
	}

	m := gomail.NewMessage()
	m.SetHeader("From", from)
	m.SetHeader("To", to)
	if bcc := os.Getenv("SMTP_BCC"); bcc != "" {
		m.SetHeader("Bcc", strings.Split(bcc, ",")...)
	}
	m.SetHeader("Subject", subject)
	m.SetBody("text/html", body)

	d := gomail.NewDialer(host, port, from, password)
	if err := d.DialAndSend(m); err != nil {
		return fmt.Errorf("email send failed: %w", err)
	}
	return nil
}
