-- Splunk outputs, in each ORGANISATION database: an explicit opt-out of TLS
-- certificate verification for a Splunk HEC.
--
-- WHY
--
-- The SIEM renderer (internal/pam/siem) always verified a Splunk HEC's
-- certificate, and an on-prem Splunk usually presents a self-signed one: every
-- event was refused at the TLS handshake. tls_skip_verify lets an
-- administrator say so for one output, deliberately. False -- verify -- unless
-- set, so no existing or future output loses verification by accident.
--
-- Numbered 033, following 032_ssh_access_events.sql. Safe to run repeatedly.

ALTER TABLE did.log_output_splunk
    ADD COLUMN IF NOT EXISTS tls_skip_verify boolean NOT NULL DEFAULT false;