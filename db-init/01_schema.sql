--
-- PostgreSQL database dump
--

-- Dumped from database version 16.1
-- Dumped by pg_dump version 16.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: did; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA did;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_conf; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.access_conf (
    user_name character varying(512),
    access character varying(512)
);


--
-- Name: account_group_rels; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.account_group_rels (
    id bigint NOT NULL,
    service_account_id integer NOT NULL,
    endpoint_group_id integer NOT NULL
);


--
-- Name: account_group_rels_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.account_group_rels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_group_rels_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.account_group_rels_id_seq OWNED BY did.account_group_rels.id;


--
-- Name: active_directories; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.active_directories (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    domain_name character varying(255) NOT NULL,
    directory_name character varying(255) NOT NULL,
    dc1 character varying(255),
    dc2 character varying(255),
    policy_id integer,
    "serviceAccountDomain" character varying,
    credential_rotation_policy_id integer,
    status character varying,
    created_at timestamp without time zone,
    last_sync_time timestamp without time zone,
    updated_at timestamp without time zone,
    port integer,
    password character varying(255),
    dc character varying(255),
    ad_host character varying(255),
    last_password_updated_time timestamp without time zone,
    ad_mfa integer,
    ad_admin_username character varying,
    identity_source character varying(50),
    integration_type character varying(50),
    sync_filter_groups character varying,
    sync_filter_ous character varying
);


--
-- Name: active_directories_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.active_directories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_directories_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.active_directories_id_seq OWNED BY did.active_directories.id;


--
-- Name: active_directory; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.active_directory (
    id integer NOT NULL,
    directory_name character varying(255) NOT NULL,
    integration_type character varying(255) DEFAULT ''::character varying NOT NULL,
    domain_id integer DEFAULT 0 NOT NULL,
    account_name character varying(255) DEFAULT ''::character varying NOT NULL,
    proxy_url text,
    app_url text,
    user_app_id integer DEFAULT 0 NOT NULL,
    org_unit_id integer DEFAULT 0 NOT NULL,
    device_id integer DEFAULT 0 NOT NULL,
    users_count integer DEFAULT 0 NOT NULL,
    group_count integer DEFAULT 0 NOT NULL,
    status_agent character varying(255) DEFAULT ''::character varying NOT NULL,
    status_groups character varying(255) DEFAULT ''::character varying NOT NULL,
    status_users character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: active_directory_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.active_directory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_directory_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.active_directory_id_seq OWNED BY did.active_directory.id;


--
-- Name: ad_access_logs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_access_logs (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    user_name character varying(255),
    domain_name character varying(255),
    log_description text,
    destination_ip character varying(45),
    component character varying(255),
    status character varying(45),
    created_at bigint DEFAULT EXTRACT(epoch FROM now()),
    source_ip character varying(45),
    sub_component character varying(255)
);


--
-- Name: ad_access_logs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_access_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_access_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_access_logs_id_seq OWNED BY did.ad_access_logs.id;


--
-- Name: ad_attributes; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_attributes (
    id integer NOT NULL,
    ad_id bigint NOT NULL,
    directory_name character varying(255) DEFAULT ''::character varying NOT NULL,
    integration_type character varying(255) DEFAULT ''::character varying NOT NULL,
    account_name character varying(255) DEFAULT ''::character varying NOT NULL,
    proxy_url character varying(255) DEFAULT ''::character varying NOT NULL,
    app_url character varying(255) DEFAULT ''::character varying NOT NULL,
    user_app_id integer DEFAULT 0 NOT NULL,
    org_unit_id integer DEFAULT 0 NOT NULL,
    device_id integer DEFAULT 0 NOT NULL,
    users_count integer DEFAULT 0 NOT NULL,
    group_count integer DEFAULT 0 NOT NULL,
    status_agent character varying(255) DEFAULT ''::character varying,
    status_groups character varying(255) DEFAULT ''::character varying,
    status_users character varying(255) DEFAULT ''::character varying
);


--
-- Name: ad_attributes_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_attributes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_attributes_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_attributes_id_seq OWNED BY did.ad_attributes.id;


--
-- Name: ad_gateways; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_gateways (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    domain_id integer,
    gateway_name character varying(255),
    gateway_ip character varying(255),
    gateway_port integer,
    status character varying(50) DEFAULT 'Active'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: ad_gateways_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_gateways_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_gateways_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_gateways_id_seq OWNED BY did.ad_gateways.id;


--
-- Name: ad_group_jobs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_group_jobs (
    id integer NOT NULL,
    ad_id character varying,
    ou character varying,
    username character varying,
    created_at character varying,
    permission_type character varying,
    permission_status character varying
);


--
-- Name: ad_group_jobs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_group_jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_group_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_group_jobs_id_seq OWNED BY did.ad_group_jobs.id;


--
-- Name: ad_group_policy_events; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_group_policy_events (
    id integer NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    domain_id integer NOT NULL,
    policy_id uuid NOT NULL,
    action character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    wallet_user character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: ad_group_policy_events_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_group_policy_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_group_policy_events_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_group_policy_events_id_seq OWNED BY did.ad_group_policy_events.id;


--
-- Name: ad_groups; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_groups (
    id integer NOT NULL,
    ad_id bigint NOT NULL,
    parent_id bigint,
    group_name character varying(255) NOT NULL,
    grouptype character varying
);


--
-- Name: ad_groups_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_groups_id_seq OWNED BY did.ad_groups.id;


--
-- Name: ad_logs_groups; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_logs_groups (
    id integer NOT NULL,
    ad_id character varying,
    ou character varying,
    username character varying,
    created_at character varying,
    source_ip character varying,
    destination_ip character varying,
    status character varying(512) DEFAULT 'Active'::character varying,
    authentication_status character varying,
    component character varying,
    sub_component character varying
);


--
-- Name: ad_logs_groups_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_logs_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_logs_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_logs_groups_id_seq OWNED BY did.ad_logs_groups.id;


--
-- Name: ad_mfa_challenges; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_mfa_challenges (
    id integer NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    gateway_id character varying NOT NULL,
    email character varying NOT NULL,
    binding_message character varying NOT NULL,
    status character varying NOT NULL,
    provider character varying NOT NULL,
    external_challenge_id character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    responded_at timestamp with time zone
);


--
-- Name: ad_mfa_challenges_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_mfa_challenges_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_mfa_challenges_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_mfa_challenges_id_seq OWNED BY did.ad_mfa_challenges.id;


--
-- Name: ad_mfa_enrollments; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_mfa_enrollments (
    id integer NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    user_id integer NOT NULL,
    email character varying NOT NULL,
    token character varying NOT NULL,
    used boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: ad_mfa_enrollments_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_mfa_enrollments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_mfa_enrollments_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_mfa_enrollments_id_seq OWNED BY did.ad_mfa_enrollments.id;


--
-- Name: ad_mfa_provider_config; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_mfa_provider_config (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    provider character varying(255) DEFAULT 'expo'::character varying,
    config jsonb,
    status character varying(50) DEFAULT 'Active'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: ad_mfa_provider_config_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_mfa_provider_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_mfa_provider_config_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_mfa_provider_config_id_seq OWNED BY did.ad_mfa_provider_config.id;


--
-- Name: ad_ous; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_ous (
    id integer NOT NULL,
    ad_id bigint NOT NULL,
    ou_name character varying(255) NOT NULL
);


--
-- Name: ad_ous_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_ous_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_ous_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_ous_id_seq OWNED BY did.ad_ous.id;


--
-- Name: ad_shadow_group_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_shadow_group_mapping (
    id integer NOT NULL,
    orgid integer NOT NULL,
    tenantid integer NOT NULL,
    adid integer NOT NULL,
    wallet_id integer NOT NULL,
    group_source character varying(255) NOT NULL,
    shadow_group_name character varying(255) NOT NULL,
    group_name character varying(255) NOT NULL,
    policy_id uuid
);


--
-- Name: ad_shadow_group_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_shadow_group_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_shadow_group_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_shadow_group_mapping_id_seq OWNED BY did.ad_shadow_group_mapping.id;


--
-- Name: ad_user_devices; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_user_devices (
    id integer NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    user_id integer NOT NULL,
    email character varying NOT NULL,
    expo_push_token character varying NOT NULL,
    platform character varying NOT NULL,
    device_name character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);


--
-- Name: ad_user_devices_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_user_devices_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_user_devices_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_user_devices_id_seq OWNED BY did.ad_user_devices.id;


--
-- Name: ad_user_group_mappings; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_user_group_mappings (
    ad_user_id integer NOT NULL,
    ad_group_id integer NOT NULL
);


--
-- Name: ad_user_ou_mappings; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_user_ou_mappings (
    ad_user_id integer NOT NULL,
    ad_ou_id integer NOT NULL
);


--
-- Name: ad_users; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ad_users (
    id integer NOT NULL,
    email_id text,
    status text,
    domain_id bigint,
    tenant_id bigint,
    cn text,
    username text,
    logoname text,
    user_type text,
    mfa_flag bigint,
    last_password_updated_time timestamp without time zone,
    business_phones text,
    display_name text,
    given_name text,
    job_title text,
    mail text,
    mobile_phone text,
    office_location text,
    preferred_language text,
    surname text,
    user_principal_name text,
    entra_id text,
    org_id bigint,
    groups text
);


--
-- Name: ad_users_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ad_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ad_users_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ad_users_id_seq OWNED BY did.ad_users.id;


--
-- Name: agent_keys; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.agent_keys (
    id integer NOT NULL,
    agent_name character varying(255) DEFAULT ''::character varying NOT NULL,
    agent_key character varying(255) DEFAULT ''::character varying NOT NULL,
    expiry timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    domain_id integer
);


--
-- Name: agent_keys_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.agent_keys_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agent_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.agent_keys_id_seq OWNED BY did.agent_keys.id;


--
-- Name: agent_logs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.agent_logs (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    public_ip character varying(50),
    component character varying(100),
    log_message text,
    host_name character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    os character varying(255)
);


--
-- Name: agent_logs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.agent_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agent_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.agent_logs_id_seq OWNED BY did.agent_logs.id;


--
-- Name: agents; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.agents (
    id integer NOT NULL,
    machine_id character varying(255) NOT NULL,
    name character varying(255),
    tags jsonb,
    role character varying(100),
    token text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: agents_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.agents_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agents_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.agents_id_seq OWNED BY did.agents.id;


--
-- Name: app_group_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.app_group_mapping (
    id integer NOT NULL,
    group_id integer NOT NULL,
    app_id integer NOT NULL
);


--
-- Name: app_group_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.app_group_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_group_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.app_group_mapping_id_seq OWNED BY did.app_group_mapping.id;


--
-- Name: apps; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.apps (
    app_id integer NOT NULL,
    app_name character varying(255) NOT NULL,
    logo character varying(255) NOT NULL,
    type_of_regn character varying(255) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    app_url text NOT NULL,
    domain_id character varying(255) DEFAULT ''::character varying NOT NULL,
    fieldmappings text NOT NULL
);


--
-- Name: apps_app_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.apps_app_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: apps_app_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.apps_app_id_seq OWNED BY did.apps.app_id;


--
-- Name: attribute_types; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.attribute_types (
    id integer NOT NULL,
    attribute_type character varying(50)
);


--
-- Name: attribute_types_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.attribute_types_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: attribute_types_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.attribute_types_id_seq OWNED BY did.attribute_types.id;


--
-- Name: audit_log; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.audit_log (
    id integer NOT NULL,
    user_id integer NOT NULL,
    email_id character varying(255) NOT NULL,
    browser character varying(255) NOT NULL,
    user_agent character varying(255) NOT NULL,
    session_time character varying(255) NOT NULL,
    session_length character varying(255) NOT NULL,
    auth_type character varying(255) NOT NULL,
    device_id integer NOT NULL
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.audit_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.audit_log_id_seq OWNED BY did.audit_log.id;


--
-- Name: auth_log; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.auth_log (
    id integer NOT NULL,
    tenant_id integer,
    org_id integer,
    username character varying(255),
    domain_name character varying(255),
    log_description text,
    destination_ip character varying(45),
    component character varying(255),
    status character varying(45),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    source_ip character varying(45),
    sub_component character varying(255),
    ts_unix_ms bigint DEFAULT (EXTRACT(epoch FROM now()))::bigint,
    gateway_id character varying(255),
    correlation_id character varying(255),
    protocol character varying(50),
    principal character varying(255),
    realm character varying(255),
    service_spn character varying(255),
    client_ip character varying(45),
    decision character varying(50),
    reason character varying(255),
    upstream_error_code integer,
    challenge_id character varying(255)
);


--
-- Name: auth_log_entries; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.auth_log_entries (
    id integer NOT NULL,
    "timestamp" character varying,
    source_ip character varying,
    service_name character varying,
    authentication character varying,
    destination_ip character varying,
    "user" character varying,
    protocol character varying
);


--
-- Name: auth_log_entries_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.auth_log_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_log_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.auth_log_entries_id_seq OWNED BY did.auth_log_entries.id;


--
-- Name: auth_log_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.auth_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_log_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.auth_log_id_seq OWNED BY did.auth_log.id;


--
-- Name: auth_logs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.auth_logs (
    id integer NOT NULL,
    org_id bigint,
    tenant_id bigint,
    log_type text,
    os text,
    ad_user text,
    ad_user_type text,
    ad_user_match text,
    ad_domain text,
    ad_ou text,
    source_endpoint text,
    source_endpoint_type text,
    source_endpoint_match text,
    destination_endpoint text,
    destination_endpoint_type text,
    destination_endpoint_match text,
    endpoint_user text,
    endpoint_user_type text,
    endpoint_user_match text,
    access_medium text,
    protocol text,
    "timestamp" integer,
    login_status text,
    sam_account_name text,
    destination_endpoint_ip text,
    source_endpoint_ip character varying
);


--
-- Name: auth_logs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

ALTER TABLE did.auth_logs ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME did.auth_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_policies; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.auth_policies (
    id integer NOT NULL,
    org_id bigint,
    tenant_id bigint,
    policy_name text,
    policy_type text,
    os text,
    ad_user text,
    ad_user_type text,
    ad_user_match text,
    ad_domain text,
    ad_ou text,
    source_endpoint text,
    source_endpoint_type text,
    source_endpoint_match text,
    destination_endpoint text,
    destination_endpoint_type text,
    destination_endpoint_match text,
    endpoint_user text,
    endpoint_user_type text,
    endpoint_user_match text,
    access_medium text,
    protocol text,
    "timestamp" integer,
    policy_status text,
    sam_account_name boolean,
    created_by bigint,
    updated_by bigint,
    auth_count bigint DEFAULT 1,
    updated_at integer,
    policy_flow character varying(8),
    wallet_users character varying(1024)
);


--
-- Name: auth_policies_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

ALTER TABLE did.auth_policies ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME did.auth_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_policy_json; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.auth_policy_json (
    id uuid,
    policy_name character varying,
    policy_type character varying,
    policy_json jsonb,
    status character varying,
    policy_invokation_count character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    created_by character varying,
    updated_by character varying,
    version integer,
    parent_id uuid,
    generated_by character varying(10) DEFAULT 'Manual'::character varying NOT NULL,
    priority integer,
    is_baseline boolean DEFAULT false,
    policy_scope character varying,
    policy_template_type character varying,
    discovery_source character varying,
    source_ad_group_id uuid
);


--
-- Name: auth_requests; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.auth_requests (
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    source_endpoint character varying(255),
    destination_endpoint character varying(255),
    os character varying(16),
    user_type character varying(16),
    username character varying(24),
    protocol character(8),
    access_mode character varying(16),
    login_status character varying(16),
    sam_account_name character varying(24),
    user_ad_domain character varying(48),
    user_ad_ou character varying(64),
    request_count integer,
    "timestamp" bigint,
    platform_user character varying(256),
    destination_endpoint_ip character varying(24),
    status character varying(24),
    source_endpoint_ip character varying
);


--
-- Name: authentication_methods; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.authentication_methods (
    id integer NOT NULL,
    tenant_id integer,
    authentication_method character varying(255),
    sso_url character varying(255),
    module_name character varying(50),
    single_sign_on_url character varying(255),
    single_logout_url character varying(255),
    metadata_url character varying(255),
    api_key character varying(255)
);


--
-- Name: authentication_methods_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.authentication_methods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: authentication_methods_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.authentication_methods_id_seq OWNED BY did.authentication_methods.id;


--
-- Name: bc_user_details; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.bc_user_details (
    id integer NOT NULL,
    dn character varying(255) DEFAULT ''::character varying NOT NULL,
    cn character varying(255) DEFAULT ''::character varying NOT NULL,
    sn character varying(255) DEFAULT ''::character varying NOT NULL,
    c character varying(255) DEFAULT ''::character varying NOT NULL,
    l character varying(255) DEFAULT ''::character varying NOT NULL,
    st character varying(255) DEFAULT ''::character varying NOT NULL,
    title character varying(255) DEFAULT ''::character varying NOT NULL,
    description character varying(255) DEFAULT ''::character varying NOT NULL,
    postal_address character varying(255) DEFAULT ''::character varying NOT NULL,
    postal_code character varying(255) DEFAULT ''::character varying NOT NULL,
    physical_delivery_office_name character varying(255) DEFAULT ''::character varying NOT NULL,
    telephone_number character varying(255) DEFAULT ''::character varying NOT NULL,
    given_name character varying(255) DEFAULT ''::character varying NOT NULL,
    generation_qualifier character varying(255) DEFAULT ''::character varying NOT NULL,
    distinguished_name character varying(255) DEFAULT ''::character varying NOT NULL,
    instance_type character varying(255) DEFAULT ''::character varying NOT NULL,
    when_created character varying(255) DEFAULT ''::character varying NOT NULL,
    when_changed character varying(255) DEFAULT ''::character varying NOT NULL,
    display_name character varying(255) DEFAULT ''::character varying NOT NULL,
    usnc_created character varying(255) DEFAULT ''::character varying NOT NULL,
    info character varying(255) DEFAULT ''::character varying NOT NULL,
    usnc_changed character varying(255) DEFAULT ''::character varying NOT NULL,
    co character varying(255) DEFAULT ''::character varying NOT NULL,
    department character varying(255) DEFAULT ''::character varying NOT NULL,
    company character varying(255) DEFAULT ''::character varying NOT NULL,
    admin_display_name character varying(255) DEFAULT ''::character varying NOT NULL,
    admin_description character varying(255) DEFAULT ''::character varying NOT NULL,
    street_address character varying(255) DEFAULT ''::character varying NOT NULL,
    employee_number character varying(255) DEFAULT ''::character varying NOT NULL,
    home_postal_address character varying(255) DEFAULT ''::character varying NOT NULL,
    user_name character varying(255) DEFAULT ''::character varying NOT NULL,
    user_account_control character varying(255) DEFAULT ''::character varying NOT NULL,
    bad_pwd_count character varying(255) DEFAULT ''::character varying NOT NULL,
    code_page text NOT NULL,
    country_code character varying(255) DEFAULT ''::character varying NOT NULL,
    employee_id character varying(255) DEFAULT ''::character varying NOT NULL,
    home_directory character varying(255) DEFAULT ''::character varying NOT NULL,
    bad_password_time character varying(255) DEFAULT ''::character varying NOT NULL,
    last_logon character varying(255) DEFAULT ''::character varying NOT NULL,
    pwd_last_set character varying(255) DEFAULT ''::character varying NOT NULL,
    primary_group_id character varying(255) DEFAULT ''::character varying NOT NULL,
    acount_expires character varying(255) DEFAULT ''::character varying NOT NULL,
    logon_count character varying(255) DEFAULT ''::character varying NOT NULL,
    sam_account_name character varying(255) DEFAULT ''::character varying NOT NULL,
    division character varying(255) DEFAULT ''::character varying NOT NULL,
    sam_account_type character varying(255) DEFAULT ''::character varying NOT NULL,
    desktop_profile character varying(255) DEFAULT ''::character varying NOT NULL,
    primary_telex_number character varying(255) DEFAULT ''::character varying NOT NULL,
    user_principal_name character varying(255) DEFAULT ''::character varying NOT NULL,
    lockout_time character varying(255) DEFAULT ''::character varying NOT NULL,
    object_category character varying(255) DEFAULT ''::character varying NOT NULL,
    account_name_history character varying(255) DEFAULT ''::character varying NOT NULL,
    ds_core_propagation_data character varying(255) DEFAULT ''::character varying NOT NULL,
    last_logon_time character varying(255) DEFAULT ''::character varying NOT NULL,
    ms_ds_last_successful_interactive_logon_time character varying(255) DEFAULT ''::character varying NOT NULL,
    ms_ds_last_failed_interactive_logon_time character varying(255) DEFAULT ''::character varying NOT NULL,
    ms_ds_failed_interactive_logon_count_at_last_successful_logon character varying(255) DEFAULT ''::character varying NOT NULL,
    mail character varying(255) DEFAULT ''::character varying NOT NULL,
    manager character varying(255) DEFAULT ''::character varying NOT NULL,
    mobile character varying(255) DEFAULT ''::character varying NOT NULL,
    department_number character varying(255) DEFAULT ''::character varying NOT NULL,
    uid_number character varying(255) DEFAULT ''::character varying NOT NULL,
    gid_number character varying(255) DEFAULT ''::character varying NOT NULL,
    gecos character varying(255) DEFAULT ''::character varying NOT NULL,
    login_shell character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: bc_user_details_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.bc_user_details_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bc_user_details_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.bc_user_details_id_seq OWNED BY did.bc_user_details.id;


--
-- Name: business_categories; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.business_categories (
    id integer NOT NULL,
    category character varying(255) NOT NULL
);


--
-- Name: business_categories_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.business_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: business_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.business_categories_id_seq OWNED BY did.business_categories.id;


--
-- Name: checkout_jobs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.checkout_jobs (
    id integer NOT NULL,
    job_name character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    epm_user_id integer NOT NULL,
    epm_machine_id integer NOT NULL,
    domain_id integer DEFAULT 0 NOT NULL,
    issuer_id integer DEFAULT 0 NOT NULL,
    user_id integer NOT NULL,
    issue_verified_credential boolean DEFAULT false NOT NULL,
    shareconnection boolean DEFAULT false NOT NULL,
    protocol character varying,
    port integer,
    credential_id integer,
    jump_server_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    assignment_time_limit character varying(255)
);


--
-- Name: checkout_jobs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.checkout_jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: checkout_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.checkout_jobs_id_seq OWNED BY did.checkout_jobs.id;


--
-- Name: client_apps; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.client_apps (
    id character varying(64) NOT NULL,
    tenant_id integer,
    org_id integer,
    user_id integer,
    app_name character varying(255),
    description character varying(1024),
    auth_method character varying(255),
    client_id character varying(128),
    client_secret character varying(128),
    app_url character varying(1024),
    auth_url character varying(1024),
    login_url character varying(1024),
    logout_url character varying(1024),
    metadata_url character varying(1024),
    app_logo character varying(1024),
    status character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: client_details; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.client_details (
    id integer NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    client_name character varying(255) NOT NULL,
    client_type character varying(255) NOT NULL,
    client_id character varying(512) NOT NULL,
    client_secret character varying(512) NOT NULL,
    created_by character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying,
    created_at bigint NOT NULL
);


--
-- Name: client_details_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.client_details_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: client_details_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.client_details_id_seq OWNED BY did.client_details.id;


--
-- Name: credential_policies; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.credential_policies (
    id integer NOT NULL,
    policy_name character varying(255) NOT NULL,
    user_type character varying(255) NOT NULL,
    rules_rotate_every character varying(255) NOT NULL,
    rules_access_credential character varying(255) NOT NULL
);


--
-- Name: credential_policies_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.credential_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.credential_policies_id_seq OWNED BY did.credential_policies.id;


--
-- Name: credential_policy_endpoints_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.credential_policy_endpoints_mapping (
    credential_policy_id integer NOT NULL,
    machine_id integer NOT NULL
);


--
-- Name: credential_policy_epm_server_group_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.credential_policy_epm_server_group_mapping (
    credential_policy_id integer NOT NULL,
    epm_server_group_id integer NOT NULL
);


--
-- Name: credential_rotation_jobs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.credential_rotation_jobs (
    id bigint NOT NULL,
    job_date character varying,
    job_hour integer,
    job_type character varying,
    credential_address character varying,
    no_of_credential_processed integer,
    processed_time bigint,
    job_status character varying,
    org_id integer,
    tenant_id integer
);


--
-- Name: credential_rotation_jobs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.credential_rotation_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_rotation_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.credential_rotation_jobs_id_seq OWNED BY did.credential_rotation_jobs.id;


--
-- Name: credential_rotation_policy; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.credential_rotation_policy (
    policy_id integer NOT NULL,
    policy_name character varying(255) NOT NULL,
    rotation_timeframe_days integer DEFAULT 0 NOT NULL,
    credential_medium character varying(255) DEFAULT ''::character varying NOT NULL,
    session_expiry_time integer DEFAULT 0 NOT NULL,
    user_type character varying(255) NOT NULL,
    domain_id bigint DEFAULT 0 NOT NULL,
    key_format character varying,
    key_encryption character varying,
    public_key_folder_path character varying,
    credential_type character varying,
    new_server_group_id integer,
    status character varying(255) DEFAULT 'Active'::character varying NOT NULL,
    last_modified timestamp without time zone DEFAULT now() NOT NULL,
    pwd_complexity integer,
    pwd_length integer,
    pwd_upper_case integer,
    pwd_lower_case integer,
    pwd_numeric integer,
    pwd_spl_char integer
);


--
-- Name: credential_rotation_policy_policy_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.credential_rotation_policy_policy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_rotation_policy_policy_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.credential_rotation_policy_policy_id_seq OWNED BY did.credential_rotation_policy.policy_id;


--
-- Name: credential_submission_queue; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.credential_submission_queue (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    credential_id integer NOT NULL,
    status character varying(255) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: credential_submission_queue_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.credential_submission_queue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_submission_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.credential_submission_queue_id_seq OWNED BY did.credential_submission_queue.id;


--
-- Name: csv_jobs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.csv_jobs (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    file_name character varying(255) DEFAULT ''::character varying NOT NULL,
    file_path character varying(255) DEFAULT ''::character varying NOT NULL,
    status character varying(255) DEFAULT 'QUEUED'::character varying NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: csv_jobs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.csv_jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: csv_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.csv_jobs_id_seq OWNED BY did.csv_jobs.id;


--
-- Name: custom_presentation_response_submission_queue; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.custom_presentation_response_submission_queue (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    presentation_request_submission_id integer NOT NULL,
    presentation_response text NOT NULL,
    status character(10) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    holder_did text
);


--
-- Name: custom_presentation_response_submission_queue_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.custom_presentation_response_submission_queue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: custom_presentation_response_submission_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.custom_presentation_response_submission_queue_id_seq OWNED BY did.custom_presentation_response_submission_queue.id;


--
-- Name: database_job_queue; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.database_job_queue (
    id integer NOT NULL,
    job_name character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    db_user_id integer NOT NULL,
    db_id integer NOT NULL,
    wallet_user_id integer NOT NULL,
    host character varying NOT NULL,
    domain_id integer DEFAULT 0 NOT NULL,
    issuer_id integer DEFAULT 0 NOT NULL,
    port integer,
    credential_id integer,
    table_name character varying NOT NULL,
    fields character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    privileges character varying,
    policy_id uuid
);


--
-- Name: database_job_queue_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.database_job_queue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: database_job_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.database_job_queue_id_seq OWNED BY did.database_job_queue.id;


--
-- Name: db_field; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.db_field (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    db_type character varying(255),
    db_id integer,
    table_name character varying(255),
    field_name character varying(255),
    created_at integer DEFAULT EXTRACT(epoch FROM now()),
    instance_id integer
);


--
-- Name: db_field_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.db_field_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: db_field_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.db_field_id_seq OWNED BY did.db_field.id;


--
-- Name: db_hosts; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.db_hosts (
    id integer NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    agent_vm_ip character varying(255) NOT NULL,
    host_vm_ip character varying(255) NOT NULL,
    port integer DEFAULT 5432,
    db_type character varying(50) DEFAULT 'postgres'::character varying,
    status character varying(50) DEFAULT 'active'::character varying,
    created_at bigint DEFAULT (EXTRACT(epoch FROM CURRENT_TIMESTAMP))::bigint,
    updated_at bigint DEFAULT (EXTRACT(epoch FROM CURRENT_TIMESTAMP))::bigint
);


--
-- Name: db_hosts_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.db_hosts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: db_hosts_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.db_hosts_id_seq OWNED BY did.db_hosts.id;


--
-- Name: db_privilege; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.db_privilege (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    db_id integer,
    user_id integer,
    privilege character varying(255),
    created_at integer DEFAULT EXTRACT(epoch FROM now()),
    instance_id integer
);


--
-- Name: db_privilege_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.db_privilege_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: db_privilege_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.db_privilege_id_seq OWNED BY did.db_privilege.id;


--
-- Name: db_synchronization; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.db_synchronization (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    db_name character varying(255),
    db_type character varying(255),
    host character varying(255),
    status character varying(45),
    created_at integer DEFAULT EXTRACT(epoch FROM now()),
    port character varying(255),
    uuid character varying(255),
    instance_id integer,
    host_id integer,
    agent_vm_ip character varying(255),
    agent_vm_private_ip character varying(255),
    agent_vm_host_name character varying(255)
);


--
-- Name: db_synchronization_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.db_synchronization_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: db_synchronization_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.db_synchronization_id_seq OWNED BY did.db_synchronization.id;


--
-- Name: db_table; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.db_table (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    db_type character varying(255),
    db_id integer,
    table_name character varying(255),
    created_at integer DEFAULT EXTRACT(epoch FROM now()),
    instance_id integer
);


--
-- Name: db_table_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.db_table_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: db_table_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.db_table_id_seq OWNED BY did.db_table.id;


--
-- Name: db_user; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.db_user (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    db_id integer,
    user_name character varying(255),
    status character varying(45),
    created_at integer DEFAULT EXTRACT(epoch FROM now()),
    role character varying(255),
    host character varying(255),
    instance_id integer,
    host_id integer,
    default_hostgroup integer,
    default_schema character varying(255)
);


--
-- Name: db_user_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.db_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: db_user_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.db_user_id_seq OWNED BY did.db_user.id;


--
-- Name: destination_endpoint; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.destination_endpoint (
    id bigint NOT NULL,
    service_account_endpoints_id integer NOT NULL,
    endpoint_id integer NOT NULL
);


--
-- Name: destination_endpoint_group; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.destination_endpoint_group (
    id bigint NOT NULL,
    service_account_endpoints_id integer NOT NULL,
    endpoint_group_id integer NOT NULL
);


--
-- Name: destination_endpoint_group_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.destination_endpoint_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: destination_endpoint_group_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.destination_endpoint_group_id_seq OWNED BY did.destination_endpoint_group.id;


--
-- Name: destination_endpoint_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.destination_endpoint_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: destination_endpoint_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.destination_endpoint_id_seq OWNED BY did.destination_endpoint.id;


--
-- Name: devices; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.devices (
    device_id integer NOT NULL,
    device_name character varying(255) NOT NULL,
    user_id integer NOT NULL,
    last_accessed timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: devices_device_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.devices_device_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devices_device_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.devices_device_id_seq OWNED BY did.devices.device_id;


--
-- Name: dit_permissions; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.dit_permissions (
    id integer,
    segment_id integer,
    dit_permission character varying,
    status character varying
);


--
-- Name: domain; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.domain (
    domain_id integer NOT NULL,
    domain_name character varying(255) NOT NULL,
    org_unit_id integer NOT NULL
);


--
-- Name: domain_domain_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.domain_domain_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: domain_domain_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.domain_domain_id_seq OWNED BY did.domain.domain_id;


--
-- Name: domain_tokens; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.domain_tokens (
    domain_id integer NOT NULL,
    domain_name character varying(255) DEFAULT ''::character varying NOT NULL,
    access_token character varying(255) DEFAULT ''::character varying NOT NULL,
    refresh_token character varying(255) DEFAULT ''::character varying NOT NULL,
    refresh_token_expiry character varying(255) DEFAULT ''::character varying NOT NULL,
    access_token_expiry character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: domain_tokens_domain_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.domain_tokens_domain_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: domain_tokens_domain_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.domain_tokens_domain_id_seq OWNED BY did.domain_tokens.domain_id;


--
-- Name: domains; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.domains (
    id integer NOT NULL,
    organization_name character varying(255) NOT NULL,
    did_method character varying(10) DEFAULT NULL::character varying
);


--
-- Name: domains_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.domains_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: domains_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.domains_id_seq OWNED BY did.domains.id;


--
-- Name: endpoint_auth_logs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.endpoint_auth_logs (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    src_ip character varying(45),
    dest_ip character varying(45),
    user_name character varying(255),
    service character varying(255),
    login_status character varying(45),
    message character varying(255),
    count integer,
    created_at bigint DEFAULT EXTRACT(epoch FROM now()),
    component character varying(45),
    host_name character varying(255)
);


--
-- Name: endpoint_auth_logs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.endpoint_auth_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: endpoint_auth_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.endpoint_auth_logs_id_seq OWNED BY did.endpoint_auth_logs.id;


--
-- Name: endpoint_group_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.endpoint_group_mapping (
    id integer NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    endpoint_name character varying(255) NOT NULL,
    ip_address character varying(255) NOT NULL,
    group_name character varying(255) NOT NULL
);


--
-- Name: endpoint_group_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.endpoint_group_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: endpoint_group_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.endpoint_group_mapping_id_seq OWNED BY did.endpoint_group_mapping.id;


--
-- Name: endpoint_groups; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.endpoint_groups (
    id bigint NOT NULL,
    group_name character varying(255)
);


--
-- Name: endpoint_groups_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.endpoint_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: endpoint_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.endpoint_groups_id_seq OWNED BY did.endpoint_groups.id;


--
-- Name: endpoint_rules; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.endpoint_rules (
    id integer NOT NULL,
    rule_name character varying,
    source_ip character varying,
    destination_ip character varying,
    status character varying,
    created_at character varying DEFAULT CURRENT_TIMESTAMP,
    username character varying,
    service character varying,
    has_permission boolean DEFAULT false NOT NULL,
    endpoint_auth_status character varying,
    protocols character varying DEFAULT 'SSH'::character varying
);


--
-- Name: endpoint_rules_conditions; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.endpoint_rules_conditions (
    id integer NOT NULL,
    rule_name character varying,
    rule_conditions character varying,
    rule_permission character varying,
    created_at character varying,
    endpoint_name character varying,
    status character varying DEFAULT 'Active'::character varying
);


--
-- Name: endpoint_rules_conditions_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.endpoint_rules_conditions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: endpoint_rules_conditions_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.endpoint_rules_conditions_id_seq OWNED BY did.endpoint_rules_conditions.id;


--
-- Name: endpoint_rules_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.endpoint_rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: endpoint_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.endpoint_rules_id_seq OWNED BY did.endpoint_rules.id;


--
-- Name: endpoint_rules_permission; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.endpoint_rules_permission (
    id integer NOT NULL,
    rule_id character varying,
    endpoint_permission_type character varying,
    endpoint_permission_value character varying,
    created_at character varying DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: endpoint_rules_permission_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.endpoint_rules_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: endpoint_rules_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.endpoint_rules_permission_id_seq OWNED BY did.endpoint_rules_permission.id;


--
-- Name: entra_config; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.entra_config (
    org_id integer NOT NULL,
    client_id text NOT NULL,
    client_secret text NOT NULL,
    last_synced_at timestamp with time zone,
    entra_tenant_id text NOT NULL,
    tenant_id integer,
    id integer NOT NULL
);


--
-- Name: entra_config_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.entra_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entra_config_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.entra_config_id_seq OWNED BY did.entra_config.id;


--
-- Name: epm_group_machine_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_group_machine_mapping (
    group_id integer NOT NULL,
    machine_id bigint NOT NULL,
    group_name character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: epm_machines; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_machines (
    machine_id integer NOT NULL,
    machine_key text NOT NULL,
    public_ip_address character varying(512) NOT NULL,
    auth_type character varying(255) NOT NULL,
    private_ip_address character varying(255) NOT NULL,
    os_id text NOT NULL,
    status character varying(255) DEFAULT ''::character varying NOT NULL,
    hostname character varying(255) DEFAULT ''::character varying NOT NULL,
    ip_address character varying(255) DEFAULT ''::character varying NOT NULL,
    localuser character varying(255) DEFAULT ''::character varying NOT NULL,
    password_policy_id integer DEFAULT 0,
    auth_code character varying(512) DEFAULT ''::character varying NOT NULL,
    jump_server_id integer DEFAULT 0,
    domain_id integer NOT NULL,
    vnc_password character varying(255) DEFAULT ''::character varying NOT NULL,
    factors character varying(512),
    status_guacd boolean,
    status_services boolean,
    instance_id bigint DEFAULT 0 NOT NULL,
    last_active character varying(255) DEFAULT '1696919403'::character varying NOT NULL,
    created_at integer DEFAULT (EXTRACT(epoch FROM now()))::integer,
    is_jumpserver boolean DEFAULT false,
    uuid character varying(255),
    epm_id integer,
    epm_public_ip_address character varying,
    epm_hostname character varying,
    auto_populate boolean DEFAULT false,
    machine_type character varying(255) DEFAULT 'endpoint'::character varying,
    description character varying(255),
    fqdn character varying(255)
);


--
-- Name: epm_machines_activity; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_machines_activity (
    id integer NOT NULL,
    epm_user_id integer NOT NULL,
    machine_id bigint DEFAULT '0'::bigint NOT NULL,
    session_recorded_time character varying(255) DEFAULT ''::character varying NOT NULL,
    session_record character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: epm_machines_activity_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.epm_machines_activity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epm_machines_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.epm_machines_activity_id_seq OWNED BY did.epm_machines_activity.id;


--
-- Name: epm_machines_machine_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.epm_machines_machine_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epm_machines_machine_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.epm_machines_machine_id_seq OWNED BY did.epm_machines.machine_id;


--
-- Name: epm_machines_password_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_machines_password_mapping (
    machine_id bigint DEFAULT '0'::bigint,
    policy_id integer DEFAULT 0
);


--
-- Name: epm_machines_users_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_machines_users_mapping (
    user_id integer NOT NULL,
    machine_id bigint NOT NULL,
    instanceid character varying(255) DEFAULT '0'::character varying NOT NULL
);


--
-- Name: epm_server_group; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_server_group (
    id integer NOT NULL,
    epm_server_group_machine_id character varying(255) DEFAULT ''::character varying NOT NULL,
    epm_server_group_machine_name character varying(255) DEFAULT ''::character varying NOT NULL,
    factors character varying(512),
    auth_type character varying(512),
    domain_id integer
);


--
-- Name: epm_server_group_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.epm_server_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epm_server_group_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.epm_server_group_id_seq OWNED BY did.epm_server_group.id;


--
-- Name: epm_server_group_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_server_group_mapping (
    id integer NOT NULL,
    epm_server_group_id integer NOT NULL,
    machine_id bigint NOT NULL,
    server_group_id integer DEFAULT 0 NOT NULL
);


--
-- Name: epm_server_group_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.epm_server_group_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epm_server_group_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.epm_server_group_mapping_id_seq OWNED BY did.epm_server_group_mapping.id;


--
-- Name: epm_users; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_users (
    id integer NOT NULL,
    epm_user_name character varying(255) DEFAULT ''::character varying NOT NULL,
    status character varying(255) DEFAULT ''::character varying NOT NULL,
    user_source character varying(255) DEFAULT ''::character varying NOT NULL,
    sync_method character varying(255) DEFAULT ''::character varying NOT NULL,
    user_type character varying(255) DEFAULT ''::character varying NOT NULL,
    password_managed character varying(255) DEFAULT ''::character varying NOT NULL,
    credential_type character varying(255) DEFAULT ''::character varying NOT NULL,
    ttl_user integer DEFAULT 0 NOT NULL,
    ttl_password integer DEFAULT 0 NOT NULL,
    home_dir character varying(255) DEFAULT ''::character varying NOT NULL,
    privileged_user smallint DEFAULT '0'::smallint NOT NULL,
    auth_method character varying(255) DEFAULT ''::character varying NOT NULL,
    custom_mapping character varying(255) DEFAULT ''::character varying NOT NULL,
    domain_id integer DEFAULT 0 NOT NULL,
    epm_user_password character varying(255) DEFAULT ''::character varying NOT NULL,
    sshkey character varying(5000) DEFAULT ''::character varying NOT NULL,
    assign smallint DEFAULT '0'::smallint NOT NULL,
    servername character varying(255) DEFAULT ''::character varying NOT NULL,
    servergroupname character varying(255) DEFAULT ''::character varying NOT NULL,
    authnullusername character varying(255) DEFAULT ''::character varying NOT NULL,
    authnullusergroup character varying(255) DEFAULT ''::character varying NOT NULL,
    motp character varying(255) DEFAULT ''::character varying NOT NULL,
    did character varying(255) DEFAULT ''::character varying NOT NULL,
    escalated_date date,
    credential_expiry character varying(255) DEFAULT ''::character varying NOT NULL,
    assignment_time_limit character varying(255) DEFAULT ''::character varying NOT NULL,
    access_credential boolean DEFAULT false NOT NULL,
    created_at integer DEFAULT (EXTRACT(epoch FROM now()))::integer,
    epm_machine_id integer,
    epm_machine_hostname character varying,
    epm_machine_public_ip_address character varying,
    epm_machine_uuid character varying,
    is_system_admin boolean DEFAULT false
);


--
-- Name: epm_users_buffer; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_users_buffer (
    id integer NOT NULL,
    epm_user_name character varying(255) DEFAULT ''::character varying NOT NULL,
    instance_id integer DEFAULT 0,
    domain_id integer DEFAULT 0 NOT NULL
);


--
-- Name: epm_users_buffer_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.epm_users_buffer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epm_users_buffer_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.epm_users_buffer_id_seq OWNED BY did.epm_users_buffer.id;


--
-- Name: epm_users_cred_management; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_users_cred_management (
    id integer NOT NULL,
    epm_user_id integer DEFAULT 0,
    encrypted_password character varying(255) DEFAULT ''::character varying NOT NULL,
    ssh_key character varying(255) DEFAULT ''::character varying NOT NULL,
    decentralized_id character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: epm_users_cred_management_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.epm_users_cred_management_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epm_users_cred_management_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.epm_users_cred_management_id_seq OWNED BY did.epm_users_cred_management.id;


--
-- Name: epm_users_group_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.epm_users_group_mapping (
    group_id integer NOT NULL,
    epm_user_id integer NOT NULL
);


--
-- Name: epm_users_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.epm_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epm_users_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.epm_users_id_seq OWNED BY did.epm_users.id;


--
-- Name: escalate_privilege; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.escalate_privilege (
    id integer NOT NULL,
    active_directory_user character varying(255) DEFAULT ''::character varying NOT NULL,
    active_directory_id integer DEFAULT 0 NOT NULL,
    epm_user_id integer DEFAULT 0,
    privileged_user boolean DEFAULT false,
    credential_expiry character varying DEFAULT '0'::character varying,
    escalation_time_limit integer DEFAULT 0,
    did_credential_expiry integer DEFAULT 0,
    wallet_id integer DEFAULT 0,
    assignment_time_limit integer DEFAULT 0
);


--
-- Name: escalate_privilege_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.escalate_privilege_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: escalate_privilege_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.escalate_privilege_id_seq OWNED BY did.escalate_privilege.id;


--
-- Name: ethereum_address; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.ethereum_address (
    id integer NOT NULL,
    cid character varying(255) NOT NULL,
    chain_address character varying(255) NOT NULL,
    date character varying(255) NOT NULL,
    hour character varying NOT NULL,
    merkle_hash character varying(255) NOT NULL,
    user_email character varying(255) NOT NULL,
    generated_hour integer,
    "time" character varying(255),
    domain_id character varying DEFAULT '7'::character varying
);


--
-- Name: ethereum_address_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.ethereum_address_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ethereum_address_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.ethereum_address_id_seq OWNED BY did.ethereum_address.id;


--
-- Name: field_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.field_mapping (
    mapping_id integer NOT NULL,
    app_id integer NOT NULL,
    source_fn character varying(255) NOT NULL,
    target_fn character varying(255) NOT NULL
);


--
-- Name: field_mapping_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.field_mapping_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: field_mapping_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.field_mapping_mapping_id_seq OWNED BY did.field_mapping.mapping_id;


--
-- Name: identity_group_relations; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.identity_group_relations (
    id bigint NOT NULL,
    workload_identity_id integer NOT NULL,
    identity_group_id integer NOT NULL
);


--
-- Name: identity_group_relations_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.identity_group_relations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_group_relations_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.identity_group_relations_id_seq OWNED BY did.identity_group_relations.id;


--
-- Name: import_jobs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.import_jobs (
    job_id integer NOT NULL,
    job_name character varying(255) NOT NULL,
    selected_group character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    created_at time(0) without time zone DEFAULT NULL::time without time zone
);


--
-- Name: import_jobs_job_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.import_jobs_job_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_jobs_job_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.import_jobs_job_id_seq OWNED BY did.import_jobs.job_id;


--
-- Name: issuer_credential_schema; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.issuer_credential_schema (
    id integer NOT NULL,
    domain_id integer NOT NULL,
    issuer_did character varying(64) NOT NULL,
    schema_id character varying(36) NOT NULL,
    schema_name character varying(255) NOT NULL,
    status character varying(20) NOT NULL,
    created_at time(0) without time zone NOT NULL,
    updated_at time(0) without time zone NOT NULL
);


--
-- Name: issuer_credential_schema_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.issuer_credential_schema_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: issuer_credential_schema_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.issuer_credential_schema_id_seq OWNED BY did.issuer_credential_schema.id;


--
-- Name: issuer_credentials; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.issuer_credentials (
    id integer NOT NULL,
    domain_id integer NOT NULL,
    issuer_id integer NOT NULL,
    schema_id integer NOT NULL,
    credential_id character varying(255) NOT NULL,
    credential_name character varying(255) NOT NULL,
    status character varying(64) NOT NULL,
    expirationdate character varying(45) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: issuer_credentials_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.issuer_credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: issuer_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.issuer_credentials_id_seq OWNED BY did.issuer_credentials.id;


--
-- Name: issuer_dids; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.issuer_dids (
    id integer NOT NULL,
    domain_id integer NOT NULL,
    did text NOT NULL,
    private_key character varying(128) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    issuer_name character varying(45) NOT NULL,
    description character varying(45) NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    is_default boolean DEFAULT false
);


--
-- Name: issuer_dids_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.issuer_dids_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: issuer_dids_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.issuer_dids_id_seq OWNED BY did.issuer_dids.id;


--
-- Name: jobs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jobs (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    job_type character varying(255) DEFAULT ''::character varying NOT NULL,
    file_path character varying(255) DEFAULT ''::character varying NOT NULL,
    status character varying(255) DEFAULT 'QUEUED'::character varying NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    file_name character varying(255) DEFAULT ''::character varying NOT NULL,
    issuer_id integer NOT NULL
);


--
-- Name: jobs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.jobs_id_seq OWNED BY did.jobs.id;


--
-- Name: jump_server; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_server (
    id integer NOT NULL,
    server_id character varying(50) DEFAULT ''::character varying NOT NULL,
    public_ip_address character varying(50) DEFAULT ''::character varying NOT NULL,
    region character varying(255) DEFAULT ''::character varying NOT NULL,
    status character varying(20) NOT NULL,
    domain_id integer NOT NULL,
    server_name character varying(255) NOT NULL,
    is_default boolean DEFAULT false,
    private_ip character varying(16),
    connect_by integer DEFAULT 0
);


--
-- Name: jump_server_connection_endpoints; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_server_connection_endpoints (
    jump_server_connection_id integer NOT NULL,
    instance_id integer NOT NULL
);


--
-- Name: jump_server_domains; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_server_domains (
    jump_server_id integer NOT NULL,
    domain_id integer NOT NULL
);


--
-- Name: jump_server_endpoint_jobs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_server_endpoint_jobs (
    id integer NOT NULL,
    jump_server_id integer NOT NULL,
    epm_machine_id integer NOT NULL,
    status character varying(20) DEFAULT 'QUEUED'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: jump_server_endpoint_jobs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.jump_server_endpoint_jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jump_server_endpoint_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.jump_server_endpoint_jobs_id_seq OWNED BY did.jump_server_endpoint_jobs.id;


--
-- Name: jump_server_endpoints; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_server_endpoints (
    jump_server_id integer NOT NULL,
    epm_machine_id integer NOT NULL
);


--
-- Name: jump_server_epm_users; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_server_epm_users (
    jump_server_id integer NOT NULL,
    epm_user_id integer NOT NULL
);


--
-- Name: jump_server_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.jump_server_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jump_server_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.jump_server_id_seq OWNED BY did.jump_server.id;


--
-- Name: jump_server_recordings; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_server_recordings (
    id integer NOT NULL,
    jump_server_connection_id integer DEFAULT 0 NOT NULL,
    recording_url character varying(1024) DEFAULT ''::character varying NOT NULL,
    recording_mime_type character varying(255) DEFAULT ''::character varying NOT NULL,
    session_recording_time character varying(255) NOT NULL,
    username character varying(512) NOT NULL,
    recording_length character varying(512) DEFAULT '00'::character varying NOT NULL,
    endpoint character varying(512) DEFAULT '00'::character varying NOT NULL,
    user_id bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: jump_server_recordings_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.jump_server_recordings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jump_server_recordings_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.jump_server_recordings_id_seq OWNED BY did.jump_server_recordings.id;


--
-- Name: jump_servers_connections; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.jump_servers_connections (
    id integer NOT NULL,
    jump_server_id integer DEFAULT 0 NOT NULL,
    epm_user_id integer DEFAULT 0 NOT NULL,
    protocol character varying(50) DEFAULT ''::character varying NOT NULL,
    port integer DEFAULT 0 NOT NULL,
    hashed_password character varying(255) NOT NULL,
    user_id bigint,
    machine_id integer,
    status character varying(32),
    expire_at timestamp without time zone
);


--
-- Name: jump_servers_connections_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.jump_servers_connections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jump_servers_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.jump_servers_connections_id_seq OWNED BY did.jump_servers_connections.id;


--
-- Name: linux_commands; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.linux_commands (
    id integer NOT NULL,
    linux_command character varying
);


--
-- Name: linux_commands_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.linux_commands_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: linux_commands_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.linux_commands_id_seq OWNED BY did.linux_commands.id;


--
-- Name: log_entries; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.log_entries (
    id integer NOT NULL,
    time_created character varying(255) NOT NULL,
    message character varying(255),
    endpoint_id character varying(255),
    event_id integer,
    provider_name character varying(255)
);


--
-- Name: log_entries_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.log_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.log_entries_id_seq OWNED BY did.log_entries.id;


--
-- Name: log_output_elasticsearch; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.log_output_elasticsearch (
    id integer NOT NULL,
    tenant_id integer NOT NULL,
    output_name character varying(255) NOT NULL,
    host character varying(255) NOT NULL,
    port integer DEFAULT 9200 NOT NULL,
    log_type character varying(255),
    index_name character varying(255) NOT NULL,
    http_user character varying(255),
    http_passwd character varying(255),
    tls boolean DEFAULT true,
    tls_verify boolean DEFAULT true
);


--
-- Name: log_output_elasticsearch_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.log_output_elasticsearch_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_output_elasticsearch_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.log_output_elasticsearch_id_seq OWNED BY did.log_output_elasticsearch.id;


--
-- Name: log_output_http; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.log_output_http (
    id integer NOT NULL,
    host character varying(255) NOT NULL,
    port integer DEFAULT 443,
    uri character varying(255) DEFAULT '/'::character varying,
    http_method character varying(10) DEFAULT 'POST'::character varying,
    content_type character varying(100) DEFAULT 'application/json'::character varying,
    custom_headers character varying,
    use_tls boolean DEFAULT true,
    tls_verify boolean DEFAULT true,
    json_date_key character varying(50) DEFAULT 'date'::character varying,
    json_date_format character varying(50) DEFAULT 'iso8601'::character varying,
    match_pattern character varying(255) DEFAULT '*'::character varying,
    retry_limit integer DEFAULT 5,
    retry_delay_sec integer DEFAULT 10,
    log_type character varying,
    tenant_id integer
);


--
-- Name: log_output_http_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.log_output_http_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_output_http_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.log_output_http_id_seq OWNED BY did.log_output_http.id;


--
-- Name: log_output_splunk; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.log_output_splunk (
    id integer NOT NULL,
    tenant_id integer NOT NULL,
    output_name character varying(255) NOT NULL,
    host character varying(255) NOT NULL,
    password character varying(255),
    auth_token character varying(255),
    http_username character varying(255),
    http_password character varying(255),
    port integer NOT NULL,
    logtype character varying(255)
);


--
-- Name: log_output_splunk_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.log_output_splunk_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_output_splunk_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.log_output_splunk_id_seq OWNED BY did.log_output_splunk.id;


--
-- Name: log_output_syslog; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.log_output_syslog (
    id integer NOT NULL,
    host character varying(255) NOT NULL,
    port integer DEFAULT 514,
    mode character varying(10) DEFAULT 'tcp'::character varying NOT NULL,
    syslog_format character varying(20) DEFAULT 'rfc3164'::character varying,
    message_key character varying(50) DEFAULT 'message'::character varying,
    tls_verify boolean DEFAULT true,
    match_pattern character varying(255) DEFAULT '*'::character varying,
    workers integer DEFAULT 1,
    retry_limit integer DEFAULT 5,
    retry_delay_sec integer DEFAULT 10,
    log_type character varying,
    tenant_id integer
);


--
-- Name: log_output_syslog_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.log_output_syslog_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_output_syslog_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.log_output_syslog_id_seq OWNED BY did.log_output_syslog.id;


--
-- Name: master_attribute_list; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.master_attribute_list (
    id integer NOT NULL,
    attribute_type_id integer,
    attribute_name character varying(255),
    parent_id character varying(512),
    attribute_label character varying(255),
    is_collected integer
);


--
-- Name: master_attribute_list_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.master_attribute_list_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: master_attribute_list_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.master_attribute_list_id_seq OWNED BY did.master_attribute_list.id;


--
-- Name: merkle_hash; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.merkle_hash (
    id integer NOT NULL,
    ldap_user character varying(255),
    local_user character varying(255),
    transaction_id character varying(255),
    merkle_hash character varying(64),
    cid character varying(255),
    merkle_status character varying(20),
    created_at character varying(255),
    generated_hour integer,
    "time" character varying(255),
    domain_id character varying DEFAULT '7'::character varying
);


--
-- Name: merkle_hash_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.merkle_hash_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merkle_hash_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.merkle_hash_id_seq OWNED BY did.merkle_hash.id;


--
-- Name: mfa_config; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.mfa_config (
    id integer NOT NULL,
    tenant_id integer,
    name character varying(255),
    description character varying(255),
    status character varying(16),
    factor_type character varying(32),
    is_default boolean DEFAULT false
);


--
-- Name: mfa_config_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.mfa_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: mfa_config_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.mfa_config_id_seq OWNED BY did.mfa_config.id;


--
-- Name: mfa_methods; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.mfa_methods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id text NOT NULL,
    method_type character varying(20) NOT NULL,
    method_data jsonb,
    enabled boolean DEFAULT false,
    verified boolean DEFAULT false,
    backup_codes text[],
    enrolled_at timestamp with time zone,
    last_used_at timestamp with time zone,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    user_id integer
);


--
-- Name: network_devices; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.network_devices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    device_type character varying NOT NULL,
    name character varying NOT NULL,
    device_id character varying NOT NULL,
    ip_address character varying NOT NULL,
    org_id integer NOT NULL,
    tenant_id integer NOT NULL,
    event_type character varying DEFAULT 'radius_auth'::character varying NOT NULL,
    nas_identifier character varying DEFAULT ''::character varying NOT NULL,
    client_ip character varying DEFAULT ''::character varying NOT NULL,
    nas_port integer NOT NULL,
    nas_port_type character varying NOT NULL,
    nas_port_id character varying(20) NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: object_classes; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.object_classes (
    id integer NOT NULL,
    class_name character varying(255) NOT NULL
);


--
-- Name: object_classes_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.object_classes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: object_classes_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.object_classes_id_seq OWNED BY did.object_classes.id;


--
-- Name: okta_configuration; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.okta_configuration (
    id integer NOT NULL,
    api character varying,
    token character varying,
    domain_id integer,
    status character varying(50) DEFAULT 'Active'::character varying
);


--
-- Name: oktalog_entries; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.oktalog_entries (
    id integer NOT NULL,
    "timestamp" character varying,
    source_ip character varying,
    user_id character varying,
    user_name character varying,
    browser character varying,
    operating_system character varying,
    city character varying,
    country character varying,
    authentication_result character varying
);


--
-- Name: oktalog_entries_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.oktalog_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oktalog_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.oktalog_entries_id_seq OWNED BY did.oktalog_entries.id;


--
-- Name: org_unit; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.org_unit (
    org_unit_id integer NOT NULL,
    org_unit_name character varying(255) NOT NULL
);


--
-- Name: org_unit_org_unit_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.org_unit_org_unit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: org_unit_org_unit_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.org_unit_org_unit_id_seq OWNED BY did.org_unit.org_unit_id;


--
-- Name: organizations; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.organizations (
    id bigint NOT NULL,
    organization_name text,
    admin_email text,
    site_url text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    status text,
    authentication_method text,
    database_status character varying,
    database_name character varying
);


--
-- Name: organizations_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.organizations_id_seq OWNED BY did.organizations.id;


--
-- Name: os_info; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.os_info (
    os_id integer NOT NULL,
    os_name character varying(255) NOT NULL
);


--
-- Name: os_info_os_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.os_info_os_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: os_info_os_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.os_info_os_id_seq OWNED BY did.os_info.os_id;


--
-- Name: password_policy; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.password_policy (
    policy_id integer NOT NULL,
    policy_name character varying(255) NOT NULL,
    rules_min_length character varying(255) DEFAULT ''::character varying NOT NULL,
    rules_max_length character varying(255) DEFAULT ''::character varying NOT NULL,
    rules_first_character character varying(255) DEFAULT ''::character varying NOT NULL,
    rules_allow_all_upperlower character varying(255) DEFAULT ''::character varying NOT NULL,
    rules_allow_all_special character varying(255) DEFAULT ''::character varying NOT NULL,
    rules_how_many_numeric character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: password_policy_policy_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.password_policy_policy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: password_policy_policy_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.password_policy_policy_id_seq OWNED BY did.password_policy.policy_id;


--
-- Name: permissions; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.permissions (
    id integer NOT NULL,
    permission character varying(255),
    permission_type integer,
    resource_type_id integer
);


--
-- Name: pgina_logs; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.pgina_logs (
    id integer NOT NULL,
    org_id integer,
    tenant_id integer,
    user_name character varying(255),
    domain_name character varying(255),
    group_name character varying(255),
    host_name character varying(255),
    log_description text,
    source_ip character varying(45),
    destination_ip character varying(45),
    component character varying(255),
    status character varying(45),
    created_at bigint DEFAULT EXTRACT(epoch FROM now()),
    sub_component character varying(255)
);


--
-- Name: pgina_logs_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.pgina_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pgina_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.pgina_logs_id_seq OWNED BY did.pgina_logs.id;


--
-- Name: platform_ad_user_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.platform_ad_user_mapping (
    user_id integer NOT NULL,
    wallet_id integer NOT NULL,
    ad_user_id integer NOT NULL,
    epm_user_id integer NOT NULL,
    service_account_id integer NOT NULL,
    credential_id integer NOT NULL,
    credential_schema_id integer NOT NULL,
    issuer_id integer NOT NULL,
    status character varying(50),
    policy_id integer NOT NULL,
    tenant_id integer NOT NULL,
    ou_id integer NOT NULL,
    verifier_id integer NOT NULL,
    endpoint_id integer NOT NULL,
    user_type character varying(256) NOT NULL
);


--
-- Name: platform_ad_user_mapping_user_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.platform_ad_user_mapping_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: platform_ad_user_mapping_user_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.platform_ad_user_mapping_user_id_seq OWNED BY did.platform_ad_user_mapping.user_id;


--
-- Name: policy_credential_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.policy_credential_mapping (
    policy_id uuid NOT NULL,
    credential_id integer NOT NULL,
    id integer NOT NULL
);


--
-- Name: policy_credential_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.policy_credential_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: policy_credential_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.policy_credential_mapping_id_seq OWNED BY did.policy_credential_mapping.id;


--
-- Name: presentation_request_submission_queue; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.presentation_request_submission_queue (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    presentation_request_bytes text,
    status character varying(20) DEFAULT 'RAISED'::character varying NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    verifier_id integer DEFAULT 1 NOT NULL,
    defination_id integer DEFAULT 1 NOT NULL,
    holder_did text,
    presentation_request_json text,
    verifier_did text,
    acknowledged smallint DEFAULT '0'::smallint NOT NULL,
    pr_type character varying,
    user_wallet_ip character varying(50)
);


--
-- Name: presentation_request_submission_queue_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.presentation_request_submission_queue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: presentation_request_submission_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.presentation_request_submission_queue_id_seq OWNED BY did.presentation_request_submission_queue.id;


--
-- Name: presentation_response_submission_queue; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.presentation_response_submission_queue (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    presentation_request_submission_id integer NOT NULL,
    presentation_response_bytes text NOT NULL,
    status character(10) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    holder_did text,
    user_wallet_ip character varying(50)
);


--
-- Name: presentation_response_submission_queue_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.presentation_response_submission_queue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: presentation_response_submission_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.presentation_response_submission_queue_id_seq OWNED BY did.presentation_response_submission_queue.id;


--
-- Name: rules; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.rules (
    id integer NOT NULL,
    rule_name character varying,
    status character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    created_by character varying(256)
);


--
-- Name: rules_condition; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.rules_condition (
    id integer NOT NULL,
    rule_id integer NOT NULL,
    attribute character varying,
    operator character varying,
    value character varying
);


--
-- Name: rules_condition_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.rules_condition_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rules_condition_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.rules_condition_id_seq OWNED BY did.rules_condition.id;


--
-- Name: rules_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rules_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.rules_id_seq OWNED BY did.rules.id;


--
-- Name: segment_attribute_values; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.segment_attribute_values (
    id integer NOT NULL,
    segment_attribute_id integer,
    attribute_value character varying(255)
);


--
-- Name: segment_attribute_values_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.segment_attribute_values_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: segment_attribute_values_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.segment_attribute_values_id_seq OWNED BY did.segment_attribute_values.id;


--
-- Name: segment_attributes; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.segment_attributes (
    id integer NOT NULL,
    segment_id integer,
    attribute_name character varying(255),
    attribute_datatype character varying(50),
    attribute_match_pattern character varying(255),
    attribute_value_occurrence integer,
    attribute_is_must boolean,
    attribute_is_optional boolean
);


--
-- Name: segment_attributes_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.segment_attributes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: segment_attributes_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.segment_attributes_id_seq OWNED BY did.segment_attributes.id;


--
-- Name: segments; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.segments (
    id integer NOT NULL,
    segments_name character varying(255),
    status character varying(512),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    segments_type character varying(512),
    bu character varying(512),
    is_dynamic character varying(512),
    app_or_endpoint character varying(512)
);


--
-- Name: segments_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.segments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: segments_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.segments_id_seq OWNED BY did.segments.id;


--
-- Name: service_account_credential_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.service_account_credential_mapping (
    id integer NOT NULL,
    source_endpoint_id integer NOT NULL,
    destination_endpoint_id integer NOT NULL,
    destination_epmuser_id integer NOT NULL,
    credential_id integer NOT NULL,
    user_source character varying(255) NOT NULL,
    status character varying(50) NOT NULL,
    user_id integer,
    eth_address character varying,
    created_at character varying,
    updated_at character varying,
    created_hour character varying,
    eth_status character varying,
    org_id integer,
    tenant_id integer,
    issuer_id integer,
    pr_submission character varying DEFAULT 'offline'::character varying NOT NULL,
    user_type character varying
);


--
-- Name: service_account_credential_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.service_account_credential_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: service_account_credential_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.service_account_credential_mapping_id_seq OWNED BY did.service_account_credential_mapping.id;


--
-- Name: service_account_delegations; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.service_account_delegations (
    id integer NOT NULL,
    user_id integer NOT NULL,
    wallet_id integer NOT NULL,
    token text,
    issuer_id integer
);


--
-- Name: service_account_delegations_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.service_account_delegations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: service_account_delegations_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.service_account_delegations_id_seq OWNED BY did.service_account_delegations.id;


--
-- Name: service_accounts; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.service_accounts (
    id bigint NOT NULL,
    domain_id integer NOT NULL,
    username character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    description text
);


--
-- Name: service_accounts_endpoints; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.service_accounts_endpoints (
    id bigint NOT NULL,
    access boolean,
    source_type character varying(100),
    destination_type character varying(100),
    service_account_id bigint NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by integer,
    wallet_id bigint NOT NULL
);


--
-- Name: service_accounts_endpoints_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.service_accounts_endpoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: service_accounts_endpoints_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.service_accounts_endpoints_id_seq OWNED BY did.service_accounts_endpoints.id;


--
-- Name: service_accounts_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.service_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: service_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.service_accounts_id_seq OWNED BY did.service_accounts.id;


--
-- Name: sid_histories; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.sid_histories (
    sid character varying(255) NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: source_endpoint; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.source_endpoint (
    id bigint NOT NULL,
    service_account_endpoints_id integer NOT NULL,
    endpoint_id integer NOT NULL
);


--
-- Name: source_endpoint_group; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.source_endpoint_group (
    id bigint NOT NULL,
    service_account_endpoints_id integer NOT NULL,
    endpoint_group_id integer NOT NULL
);


--
-- Name: source_endpoint_group_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.source_endpoint_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_endpoint_group_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.source_endpoint_group_id_seq OWNED BY did.source_endpoint_group.id;


--
-- Name: source_endpoint_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.source_endpoint_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_endpoint_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.source_endpoint_id_seq OWNED BY did.source_endpoint.id;


--
-- Name: sudoers_permission; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.sudoers_permission (
    alias character varying(512),
    sudoers_user character varying(512),
    sudoers_host character varying(512),
    command character varying(512),
    hostname character varying,
    id integer NOT NULL
);


--
-- Name: sudoers_permission_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.sudoers_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sudoers_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.sudoers_permission_id_seq OWNED BY did.sudoers_permission.id;


--
-- Name: system_log_entries; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.system_log_entries (
    id integer NOT NULL,
    time_created character varying(255) NOT NULL,
    message character varying(255),
    endpoint_id character varying(255),
    event_id integer,
    provider_name character varying(255)
);


--
-- Name: system_log_entries_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.system_log_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_log_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.system_log_entries_id_seq OWNED BY did.system_log_entries.id;


--
-- Name: tenant_mfa_config; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.tenant_mfa_config (
    tenant_id character varying(255),
    factor_id integer DEFAULT '-1'::integer,
    factor_order integer DEFAULT '-1'::integer,
    status character varying(16) DEFAULT 'Active'::character varying,
    factor_type character varying(32)
);


--
-- Name: tenant_setup; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.tenant_setup (
    id integer NOT NULL,
    tenant_id character varying(255) NOT NULL,
    setup_name character varying NOT NULL,
    setup_status character varying(255) NOT NULL,
    parent_id integer,
    tenant_status character varying
);


--
-- Name: tenant_setup_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.tenant_setup_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenant_setup_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.tenant_setup_id_seq OWNED BY did.tenant_setup.id;


--
-- Name: tenant_vault_config; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.tenant_vault_config (
    id integer NOT NULL,
    tenant_id character varying(512),
    vault_type character varying(512),
    root_token character varying(1024),
    port character varying(524),
    ip_address character varying(524)
);


--
-- Name: tenant_vault_config_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.tenant_vault_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenant_vault_config_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.tenant_vault_config_id_seq OWNED BY did.tenant_vault_config.id;


--
-- Name: tenants; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.tenants (
    id bigint NOT NULL,
    tenant_name text,
    admin_email text,
    site_url text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    organization_id bigint,
    status text,
    authentication_method character varying,
    platform_mfa integer,
    mfa_devices integer,
    authentication_policy integer,
    sso_mfa integer,
    entity_authentication integer,
    connection_mode integer,
    credential_store integer,
    credential_share_mode integer,
    credential_mode integer DEFAULT 0,
    vault_flag character varying,
    sso_mfa_end_user integer DEFAULT 0,
    end_user_mfa_cache integer DEFAULT 0 NOT NULL,
    admin_mfa_cache integer DEFAULT 0 NOT NULL,
    default_issuer character varying,
    is_dit_enabled character varying,
    time_zone character varying,
    log_output_name character varying,
    image_url character varying(100),
    session_recording_key character varying(100),
    session_recording_secret character varying(100),
    session_recording_region character varying(100),
    bucket_name character varying(255),
    disable_root_access boolean DEFAULT true
);


--
-- Name: tenants_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.tenants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenants_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.tenants_id_seq OWNED BY did.tenants.id;


--
-- Name: transactions; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.transactions (
    id integer NOT NULL,
    cid character varying(512) NOT NULL,
    chain_address character varying(512),
    transaction_type character varying(512) NOT NULL,
    ldap_user character varying(512) NOT NULL,
    local_user character varying(512) NOT NULL,
    resource_type character varying(512) NOT NULL,
    resource_ip character varying(512) NOT NULL,
    user_ip character varying(512) NOT NULL,
    date_time character varying(512) NOT NULL,
    transaction_status character varying(512) NOT NULL,
    merkle_hash character varying(512) NOT NULL,
    merkle_status character varying DEFAULT 'NEW'::character varying NOT NULL,
    domain_id character varying DEFAULT '1'::character varying,
    transaction_message character varying(512),
    generated_hour integer,
    "time" character varying(255)
);


--
-- Name: transactions_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.transactions_id_seq OWNED BY did.transactions.id;


--
-- Name: trusted_attributes; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.trusted_attributes (
    id integer NOT NULL,
    user_name character varying,
    trusted_device character varying(512),
    trusted_network character varying(255),
    trusted_city character varying(512),
    trusted_state character varying(512),
    trusted_country character varying(512),
    trusted_region character varying,
    last_updated timestamp without time zone
);


--
-- Name: trusted_attributes_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.trusted_attributes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trusted_attributes_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.trusted_attributes_id_seq OWNED BY did.trusted_attributes.id;


--
-- Name: user_access_url; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_access_url (
    user_role_id integer,
    url character varying(1024)
);


--
-- Name: user_ad_groups; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_ad_groups (
    user_id integer NOT NULL,
    group_id bigint NOT NULL
);


--
-- Name: user_app; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_app (
    user_app_id integer NOT NULL,
    user_id integer NOT NULL,
    app_id integer NOT NULL
);


--
-- Name: user_app_user_app_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_app_user_app_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_app_user_app_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_app_user_app_id_seq OWNED BY did.user_app.user_app_id;


--
-- Name: user_auth_stats_count; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_auth_stats_count (
    id integer NOT NULL,
    username character varying,
    groupname character varying,
    identity_type character varying,
    identity character varying,
    auth_status character varying,
    auth_count integer,
    last_updated_time timestamp without time zone
);


--
-- Name: user_auth_stats_count_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_auth_stats_count_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_auth_stats_count_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_auth_stats_count_id_seq OWNED BY did.user_auth_stats_count.id;


--
-- Name: user_business_categories; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_business_categories (
    user_id integer NOT NULL,
    business_category_id bigint NOT NULL
);


--
-- Name: user_credential_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_credential_mapping (
    id integer NOT NULL,
    epm_user_id integer NOT NULL,
    credential_id integer NOT NULL,
    user_source character varying(255) DEFAULT NULL::character varying NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL
);


--
-- Name: user_credential_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_credential_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_credential_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_credential_mapping_id_seq OWNED BY did.user_credential_mapping.id;


--
-- Name: user_creds; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_creds (
    id integer NOT NULL,
    user_id integer NOT NULL,
    pub_key text NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_creds_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_creds_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_creds_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_creds_id_seq OWNED BY did.user_creds.id;


--
-- Name: user_group; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_group (
    group_id integer NOT NULL,
    group_name character varying(255) NOT NULL,
    roles character varying(255) DEFAULT ''::character varying NOT NULL,
    otp_method character varying(255) DEFAULT ''::character varying NOT NULL,
    metadata character varying(255) DEFAULT ''::character varying NOT NULL,
    domain_id character varying(255) DEFAULT ''::character varying NOT NULL,
    base_dn character varying(255) DEFAULT ''::character varying NOT NULL,
    cn character varying(255) DEFAULT ''::character varying NOT NULL,
    ou character varying(255) DEFAULT ''::character varying NOT NULL,
    fieldmappings character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: user_group_group_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_group_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_group_group_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_group_group_id_seq OWNED BY did.user_group.group_id;


--
-- Name: user_group_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_group_mapping (
    id integer NOT NULL,
    group_id integer NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: user_group_mapping_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_group_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_group_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_group_mapping_id_seq OWNED BY did.user_group_mapping.id;


--
-- Name: user_mfa_config; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_mfa_config (
    user_id integer NOT NULL,
    tenant_id integer NOT NULL,
    org_id integer NOT NULL,
    app_id integer NOT NULL,
    mfa_type integer NOT NULL,
    mfa_detail text,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: user_object_classes; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_object_classes (
    object_class_id bigint NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: user_privileges; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_privileges (
    id integer NOT NULL,
    userid character varying(512) NOT NULL,
    resource_name character varying(512) NOT NULL,
    resource_type character varying(512) NOT NULL,
    status_code character varying(50) NOT NULL,
    approved_by character varying(512),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone,
    resource_path character varying(512),
    endpoints character varying(512),
    operations character varying(512) NOT NULL,
    user_roles_permission_id integer NOT NULL
);


--
-- Name: user_privileges_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_privileges_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_privileges_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_privileges_id_seq OWNED BY did.user_privileges.id;


--
-- Name: user_privileges_user_roles_permission_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_privileges_user_roles_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_privileges_user_roles_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_privileges_user_roles_permission_id_seq OWNED BY did.user_privileges.user_roles_permission_id;


--
-- Name: user_roles_permission; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_roles_permission (
    id integer NOT NULL,
    role character varying(255) DEFAULT ''::character varying(1) NOT NULL,
    permissions character varying(255) DEFAULT ''::character varying(1) NOT NULL
);


--
-- Name: user_roles_permission_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_roles_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_roles_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_roles_permission_id_seq OWNED BY did.user_roles_permission.id;


--
-- Name: user_segment_permission; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_segment_permission (
    id integer NOT NULL,
    user_id integer,
    segment_id integer,
    permission_id integer,
    permission_type integer,
    status character varying(50) DEFAULT 'Active'::character varying
);


--
-- Name: user_verifiable_credentials; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_verifiable_credentials (
    id integer NOT NULL,
    domain_id integer NOT NULL,
    issuer_did character varying(64) NOT NULL,
    holder_did character varying(64) NOT NULL,
    vc_id character varying(64) DEFAULT NULL::character varying,
    status character varying(45) NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_verifiable_credentials_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_verifiable_credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_verifiable_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_verifiable_credentials_id_seq OWNED BY did.user_verifiable_credentials.id;


--
-- Name: user_wallet_credentials; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_wallet_credentials (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    user_id integer NOT NULL,
    credential_id integer NOT NULL,
    acknowledgement character varying(10) DEFAULT 'ASSIGNED'::character varying NOT NULL
);


--
-- Name: user_wallet_credentials_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_wallet_credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_wallet_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_wallet_credentials_id_seq OWNED BY did.user_wallet_credentials.id;


--
-- Name: user_wallets; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.user_wallets (
    id integer NOT NULL,
    domain_id integer NOT NULL,
    wallet_url character varying(64) NOT NULL,
    user_id integer NOT NULL,
    status character varying(64) NOT NULL,
    wallet_key character varying(45) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    registered_country character varying,
    registered_state character varying,
    registered_city character varying,
    device_id character varying,
    coord character varying,
    biometric_protected boolean,
    device_os character varying,
    network character varying(255)
);


--
-- Name: user_wallets_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.user_wallets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_wallets_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.user_wallets_id_seq OWNED BY did.user_wallets.id;


--
-- Name: users; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.users (
    user_id integer NOT NULL,
    email_address character varying(255) DEFAULT ''::character varying NOT NULL,
    phone_number character varying(255) DEFAULT ''::character varying NOT NULL,
    city character varying(255) DEFAULT ''::character varying NOT NULL,
    country character varying(255) DEFAULT ''::character varying NOT NULL,
    industry character varying(255) DEFAULT ''::character varying NOT NULL,
    organization character varying(255) DEFAULT ''::character varying NOT NULL,
    company_headcount character varying(255) DEFAULT ''::character varying NOT NULL,
    firstname character varying(255) DEFAULT ''::character varying NOT NULL,
    lastname character varying(255) DEFAULT ''::character varying NOT NULL,
    address character varying(255) DEFAULT ''::character varying NOT NULL,
    user_password character varying(255) DEFAULT ''::character varying NOT NULL,
    domain_id character varying,
    status character varying(255) DEFAULT ''::character varying NOT NULL,
    otp_method character varying(255) DEFAULT ''::character varying NOT NULL,
    metadata character varying(255) DEFAULT ''::character varying NOT NULL,
    dn character varying(255) DEFAULT ''::character varying NOT NULL,
    user_role_id smallint DEFAULT '0'::smallint NOT NULL,
    logon_name character varying(255) DEFAULT ''::character varying NOT NULL,
    org_id integer,
    first_login character varying(255),
    created_at integer DEFAULT (EXTRACT(epoch FROM now()))::integer
);


--
-- Name: users_dids; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.users_dids (
    id integer NOT NULL,
    user_id integer NOT NULL,
    did character varying(64) NOT NULL,
    private_key character varying(128) NOT NULL,
    issuer_did character varying(64) NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    domain_id integer NOT NULL,
    description character varying(45) NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    did_name character varying(45) NOT NULL
);


--
-- Name: users_dids_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.users_dids_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_dids_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.users_dids_id_seq OWNED BY did.users_dids.id;


--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.users_user_id_seq OWNED BY did.users.user_id;


--
-- Name: verifiable_credentials; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.verifiable_credentials (
    id integer NOT NULL,
    domain_id integer NOT NULL,
    issuer_id integer NOT NULL,
    credential_id character varying(255) NOT NULL,
    status character varying(15) DEFAULT 'INACTIVE'::character varying NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: verifiable_credentials_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.verifiable_credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: verifiable_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.verifiable_credentials_id_seq OWNED BY did.verifiable_credentials.id;


--
-- Name: verifier_dids; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.verifier_dids (
    id integer NOT NULL,
    did character varying(64) NOT NULL,
    domain_id integer NOT NULL,
    issuer_id integer NOT NULL,
    private_key character varying(128) DEFAULT NULL::character varying
);


--
-- Name: verifier_dids_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.verifier_dids_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: verifier_dids_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.verifier_dids_id_seq OWNED BY did.verifier_dids.id;


--
-- Name: wallet_user_ad_mapping; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.wallet_user_ad_mapping (
    ad_id integer NOT NULL,
    wallet_user_id integer NOT NULL,
    tenant_id integer NOT NULL,
    ad_domain_id integer NOT NULL
);


--
-- Name: wallet_user_ad_mapping_ad_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.wallet_user_ad_mapping_ad_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_user_ad_mapping_ad_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.wallet_user_ad_mapping_ad_id_seq OWNED BY did.wallet_user_ad_mapping.ad_id;


--
-- Name: workload_identities; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.workload_identities (
    id bigint NOT NULL,
    domain_id integer NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL
);


--
-- Name: workload_identities_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.workload_identities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workload_identities_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.workload_identities_id_seq OWNED BY did.workload_identities.id;


--
-- Name: workload_identity_groups; Type: TABLE; Schema: did; Owner: -
--

CREATE TABLE did.workload_identity_groups (
    id bigint NOT NULL,
    domain_id integer NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: workload_identity_groups_id_seq; Type: SEQUENCE; Schema: did; Owner: -
--

CREATE SEQUENCE did.workload_identity_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workload_identity_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: did; Owner: -
--

ALTER SEQUENCE did.workload_identity_groups_id_seq OWNED BY did.workload_identity_groups.id;


--
-- Name: account_group_rels id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.account_group_rels ALTER COLUMN id SET DEFAULT nextval('did.account_group_rels_id_seq'::regclass);


--
-- Name: active_directories id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.active_directories ALTER COLUMN id SET DEFAULT nextval('did.active_directories_id_seq'::regclass);


--
-- Name: active_directory id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.active_directory ALTER COLUMN id SET DEFAULT nextval('did.active_directory_id_seq'::regclass);


--
-- Name: ad_access_logs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_access_logs ALTER COLUMN id SET DEFAULT nextval('did.ad_access_logs_id_seq'::regclass);


--
-- Name: ad_attributes id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_attributes ALTER COLUMN id SET DEFAULT nextval('did.ad_attributes_id_seq'::regclass);


--
-- Name: ad_gateways id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_gateways ALTER COLUMN id SET DEFAULT nextval('did.ad_gateways_id_seq'::regclass);


--
-- Name: ad_group_jobs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_group_jobs ALTER COLUMN id SET DEFAULT nextval('did.ad_group_jobs_id_seq'::regclass);


--
-- Name: ad_group_policy_events id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_group_policy_events ALTER COLUMN id SET DEFAULT nextval('did.ad_group_policy_events_id_seq'::regclass);


--
-- Name: ad_groups id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_groups ALTER COLUMN id SET DEFAULT nextval('did.ad_groups_id_seq'::regclass);


--
-- Name: ad_logs_groups id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_logs_groups ALTER COLUMN id SET DEFAULT nextval('did.ad_logs_groups_id_seq'::regclass);


--
-- Name: ad_mfa_challenges id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_mfa_challenges ALTER COLUMN id SET DEFAULT nextval('did.ad_mfa_challenges_id_seq'::regclass);


--
-- Name: ad_mfa_enrollments id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_mfa_enrollments ALTER COLUMN id SET DEFAULT nextval('did.ad_mfa_enrollments_id_seq'::regclass);


--
-- Name: ad_mfa_provider_config id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_mfa_provider_config ALTER COLUMN id SET DEFAULT nextval('did.ad_mfa_provider_config_id_seq'::regclass);


--
-- Name: ad_ous id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_ous ALTER COLUMN id SET DEFAULT nextval('did.ad_ous_id_seq'::regclass);


--
-- Name: ad_shadow_group_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_shadow_group_mapping ALTER COLUMN id SET DEFAULT nextval('did.ad_shadow_group_mapping_id_seq'::regclass);


--
-- Name: ad_user_devices id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_user_devices ALTER COLUMN id SET DEFAULT nextval('did.ad_user_devices_id_seq'::regclass);


--
-- Name: ad_users id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_users ALTER COLUMN id SET DEFAULT nextval('did.ad_users_id_seq'::regclass);


--
-- Name: agent_keys id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.agent_keys ALTER COLUMN id SET DEFAULT nextval('did.agent_keys_id_seq'::regclass);


--
-- Name: agent_logs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.agent_logs ALTER COLUMN id SET DEFAULT nextval('did.agent_logs_id_seq'::regclass);


--
-- Name: agents id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.agents ALTER COLUMN id SET DEFAULT nextval('did.agents_id_seq'::regclass);


--
-- Name: app_group_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.app_group_mapping ALTER COLUMN id SET DEFAULT nextval('did.app_group_mapping_id_seq'::regclass);


--
-- Name: apps app_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.apps ALTER COLUMN app_id SET DEFAULT nextval('did.apps_app_id_seq'::regclass);


--
-- Name: attribute_types id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.attribute_types ALTER COLUMN id SET DEFAULT nextval('did.attribute_types_id_seq'::regclass);


--
-- Name: audit_log id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.audit_log ALTER COLUMN id SET DEFAULT nextval('did.audit_log_id_seq'::regclass);


--
-- Name: auth_log id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.auth_log ALTER COLUMN id SET DEFAULT nextval('did.auth_log_id_seq'::regclass);


--
-- Name: auth_log_entries id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.auth_log_entries ALTER COLUMN id SET DEFAULT nextval('did.auth_log_entries_id_seq'::regclass);


--
-- Name: authentication_methods id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.authentication_methods ALTER COLUMN id SET DEFAULT nextval('did.authentication_methods_id_seq'::regclass);


--
-- Name: bc_user_details id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.bc_user_details ALTER COLUMN id SET DEFAULT nextval('did.bc_user_details_id_seq'::regclass);


--
-- Name: business_categories id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.business_categories ALTER COLUMN id SET DEFAULT nextval('did.business_categories_id_seq'::regclass);


--
-- Name: checkout_jobs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.checkout_jobs ALTER COLUMN id SET DEFAULT nextval('did.checkout_jobs_id_seq'::regclass);


--
-- Name: client_details id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.client_details ALTER COLUMN id SET DEFAULT nextval('did.client_details_id_seq'::regclass);


--
-- Name: credential_policies id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_policies ALTER COLUMN id SET DEFAULT nextval('did.credential_policies_id_seq'::regclass);


--
-- Name: credential_rotation_jobs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_rotation_jobs ALTER COLUMN id SET DEFAULT nextval('did.credential_rotation_jobs_id_seq'::regclass);


--
-- Name: credential_rotation_policy policy_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_rotation_policy ALTER COLUMN policy_id SET DEFAULT nextval('did.credential_rotation_policy_policy_id_seq'::regclass);


--
-- Name: credential_submission_queue id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_submission_queue ALTER COLUMN id SET DEFAULT nextval('did.credential_submission_queue_id_seq'::regclass);


--
-- Name: csv_jobs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.csv_jobs ALTER COLUMN id SET DEFAULT nextval('did.csv_jobs_id_seq'::regclass);


--
-- Name: custom_presentation_response_submission_queue id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.custom_presentation_response_submission_queue ALTER COLUMN id SET DEFAULT nextval('did.custom_presentation_response_submission_queue_id_seq'::regclass);


--
-- Name: database_job_queue id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.database_job_queue ALTER COLUMN id SET DEFAULT nextval('did.database_job_queue_id_seq'::regclass);


--
-- Name: db_field id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_field ALTER COLUMN id SET DEFAULT nextval('did.db_field_id_seq'::regclass);


--
-- Name: db_hosts id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_hosts ALTER COLUMN id SET DEFAULT nextval('did.db_hosts_id_seq'::regclass);


--
-- Name: db_privilege id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_privilege ALTER COLUMN id SET DEFAULT nextval('did.db_privilege_id_seq'::regclass);


--
-- Name: db_synchronization id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_synchronization ALTER COLUMN id SET DEFAULT nextval('did.db_synchronization_id_seq'::regclass);


--
-- Name: db_table id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_table ALTER COLUMN id SET DEFAULT nextval('did.db_table_id_seq'::regclass);


--
-- Name: db_user id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_user ALTER COLUMN id SET DEFAULT nextval('did.db_user_id_seq'::regclass);


--
-- Name: destination_endpoint id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.destination_endpoint ALTER COLUMN id SET DEFAULT nextval('did.destination_endpoint_id_seq'::regclass);


--
-- Name: destination_endpoint_group id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.destination_endpoint_group ALTER COLUMN id SET DEFAULT nextval('did.destination_endpoint_group_id_seq'::regclass);


--
-- Name: devices device_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.devices ALTER COLUMN device_id SET DEFAULT nextval('did.devices_device_id_seq'::regclass);


--
-- Name: domain domain_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.domain ALTER COLUMN domain_id SET DEFAULT nextval('did.domain_domain_id_seq'::regclass);


--
-- Name: domain_tokens domain_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.domain_tokens ALTER COLUMN domain_id SET DEFAULT nextval('did.domain_tokens_domain_id_seq'::regclass);


--
-- Name: domains id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.domains ALTER COLUMN id SET DEFAULT nextval('did.domains_id_seq'::regclass);


--
-- Name: endpoint_auth_logs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_auth_logs ALTER COLUMN id SET DEFAULT nextval('did.endpoint_auth_logs_id_seq'::regclass);


--
-- Name: endpoint_group_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_group_mapping ALTER COLUMN id SET DEFAULT nextval('did.endpoint_group_mapping_id_seq'::regclass);


--
-- Name: endpoint_groups id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_groups ALTER COLUMN id SET DEFAULT nextval('did.endpoint_groups_id_seq'::regclass);


--
-- Name: endpoint_rules id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_rules ALTER COLUMN id SET DEFAULT nextval('did.endpoint_rules_id_seq'::regclass);


--
-- Name: endpoint_rules_conditions id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_rules_conditions ALTER COLUMN id SET DEFAULT nextval('did.endpoint_rules_conditions_id_seq'::regclass);


--
-- Name: endpoint_rules_permission id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_rules_permission ALTER COLUMN id SET DEFAULT nextval('did.endpoint_rules_permission_id_seq'::regclass);


--
-- Name: entra_config id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.entra_config ALTER COLUMN id SET DEFAULT nextval('did.entra_config_id_seq'::regclass);


--
-- Name: epm_machines machine_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_machines ALTER COLUMN machine_id SET DEFAULT nextval('did.epm_machines_machine_id_seq'::regclass);


--
-- Name: epm_machines_activity id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_machines_activity ALTER COLUMN id SET DEFAULT nextval('did.epm_machines_activity_id_seq'::regclass);


--
-- Name: epm_server_group id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_server_group ALTER COLUMN id SET DEFAULT nextval('did.epm_server_group_id_seq'::regclass);


--
-- Name: epm_server_group_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_server_group_mapping ALTER COLUMN id SET DEFAULT nextval('did.epm_server_group_mapping_id_seq'::regclass);


--
-- Name: epm_users id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_users ALTER COLUMN id SET DEFAULT nextval('did.epm_users_id_seq'::regclass);


--
-- Name: epm_users_buffer id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_users_buffer ALTER COLUMN id SET DEFAULT nextval('did.epm_users_buffer_id_seq'::regclass);


--
-- Name: epm_users_cred_management id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_users_cred_management ALTER COLUMN id SET DEFAULT nextval('did.epm_users_cred_management_id_seq'::regclass);


--
-- Name: escalate_privilege id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.escalate_privilege ALTER COLUMN id SET DEFAULT nextval('did.escalate_privilege_id_seq'::regclass);


--
-- Name: ethereum_address id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ethereum_address ALTER COLUMN id SET DEFAULT nextval('did.ethereum_address_id_seq'::regclass);


--
-- Name: field_mapping mapping_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.field_mapping ALTER COLUMN mapping_id SET DEFAULT nextval('did.field_mapping_mapping_id_seq'::regclass);


--
-- Name: identity_group_relations id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.identity_group_relations ALTER COLUMN id SET DEFAULT nextval('did.identity_group_relations_id_seq'::regclass);


--
-- Name: import_jobs job_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.import_jobs ALTER COLUMN job_id SET DEFAULT nextval('did.import_jobs_job_id_seq'::regclass);


--
-- Name: issuer_credential_schema id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.issuer_credential_schema ALTER COLUMN id SET DEFAULT nextval('did.issuer_credential_schema_id_seq'::regclass);


--
-- Name: issuer_credentials id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.issuer_credentials ALTER COLUMN id SET DEFAULT nextval('did.issuer_credentials_id_seq'::regclass);


--
-- Name: issuer_dids id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.issuer_dids ALTER COLUMN id SET DEFAULT nextval('did.issuer_dids_id_seq'::regclass);


--
-- Name: jobs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jobs ALTER COLUMN id SET DEFAULT nextval('did.jobs_id_seq'::regclass);


--
-- Name: jump_server id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_server ALTER COLUMN id SET DEFAULT nextval('did.jump_server_id_seq'::regclass);


--
-- Name: jump_server_endpoint_jobs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_server_endpoint_jobs ALTER COLUMN id SET DEFAULT nextval('did.jump_server_endpoint_jobs_id_seq'::regclass);


--
-- Name: jump_server_recordings id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_server_recordings ALTER COLUMN id SET DEFAULT nextval('did.jump_server_recordings_id_seq'::regclass);


--
-- Name: jump_servers_connections id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_servers_connections ALTER COLUMN id SET DEFAULT nextval('did.jump_servers_connections_id_seq'::regclass);


--
-- Name: linux_commands id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.linux_commands ALTER COLUMN id SET DEFAULT nextval('did.linux_commands_id_seq'::regclass);


--
-- Name: log_entries id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_entries ALTER COLUMN id SET DEFAULT nextval('did.log_entries_id_seq'::regclass);


--
-- Name: log_output_elasticsearch id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_elasticsearch ALTER COLUMN id SET DEFAULT nextval('did.log_output_elasticsearch_id_seq'::regclass);


--
-- Name: log_output_http id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_http ALTER COLUMN id SET DEFAULT nextval('did.log_output_http_id_seq'::regclass);


--
-- Name: log_output_splunk id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_splunk ALTER COLUMN id SET DEFAULT nextval('did.log_output_splunk_id_seq'::regclass);


--
-- Name: log_output_syslog id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_syslog ALTER COLUMN id SET DEFAULT nextval('did.log_output_syslog_id_seq'::regclass);


--
-- Name: master_attribute_list id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.master_attribute_list ALTER COLUMN id SET DEFAULT nextval('did.master_attribute_list_id_seq'::regclass);


--
-- Name: merkle_hash id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.merkle_hash ALTER COLUMN id SET DEFAULT nextval('did.merkle_hash_id_seq'::regclass);


--
-- Name: mfa_config id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.mfa_config ALTER COLUMN id SET DEFAULT nextval('did.mfa_config_id_seq'::regclass);


--
-- Name: object_classes id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.object_classes ALTER COLUMN id SET DEFAULT nextval('did.object_classes_id_seq'::regclass);


--
-- Name: oktalog_entries id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.oktalog_entries ALTER COLUMN id SET DEFAULT nextval('did.oktalog_entries_id_seq'::regclass);


--
-- Name: org_unit org_unit_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.org_unit ALTER COLUMN org_unit_id SET DEFAULT nextval('did.org_unit_org_unit_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.organizations ALTER COLUMN id SET DEFAULT nextval('did.organizations_id_seq'::regclass);


--
-- Name: os_info os_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.os_info ALTER COLUMN os_id SET DEFAULT nextval('did.os_info_os_id_seq'::regclass);


--
-- Name: password_policy policy_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.password_policy ALTER COLUMN policy_id SET DEFAULT nextval('did.password_policy_policy_id_seq'::regclass);


--
-- Name: pgina_logs id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.pgina_logs ALTER COLUMN id SET DEFAULT nextval('did.pgina_logs_id_seq'::regclass);


--
-- Name: platform_ad_user_mapping user_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.platform_ad_user_mapping ALTER COLUMN user_id SET DEFAULT nextval('did.platform_ad_user_mapping_user_id_seq'::regclass);


--
-- Name: policy_credential_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.policy_credential_mapping ALTER COLUMN id SET DEFAULT nextval('did.policy_credential_mapping_id_seq'::regclass);


--
-- Name: presentation_request_submission_queue id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.presentation_request_submission_queue ALTER COLUMN id SET DEFAULT nextval('did.presentation_request_submission_queue_id_seq'::regclass);


--
-- Name: presentation_response_submission_queue id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.presentation_response_submission_queue ALTER COLUMN id SET DEFAULT nextval('did.presentation_response_submission_queue_id_seq'::regclass);


--
-- Name: rules id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.rules ALTER COLUMN id SET DEFAULT nextval('did.rules_id_seq'::regclass);


--
-- Name: rules_condition id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.rules_condition ALTER COLUMN id SET DEFAULT nextval('did.rules_condition_id_seq'::regclass);


--
-- Name: segment_attribute_values id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.segment_attribute_values ALTER COLUMN id SET DEFAULT nextval('did.segment_attribute_values_id_seq'::regclass);


--
-- Name: segment_attributes id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.segment_attributes ALTER COLUMN id SET DEFAULT nextval('did.segment_attributes_id_seq'::regclass);


--
-- Name: segments id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.segments ALTER COLUMN id SET DEFAULT nextval('did.segments_id_seq'::regclass);


--
-- Name: service_account_credential_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_account_credential_mapping ALTER COLUMN id SET DEFAULT nextval('did.service_account_credential_mapping_id_seq'::regclass);


--
-- Name: service_account_delegations id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_account_delegations ALTER COLUMN id SET DEFAULT nextval('did.service_account_delegations_id_seq'::regclass);


--
-- Name: service_accounts id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_accounts ALTER COLUMN id SET DEFAULT nextval('did.service_accounts_id_seq'::regclass);


--
-- Name: service_accounts_endpoints id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_accounts_endpoints ALTER COLUMN id SET DEFAULT nextval('did.service_accounts_endpoints_id_seq'::regclass);


--
-- Name: source_endpoint id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.source_endpoint ALTER COLUMN id SET DEFAULT nextval('did.source_endpoint_id_seq'::regclass);


--
-- Name: source_endpoint_group id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.source_endpoint_group ALTER COLUMN id SET DEFAULT nextval('did.source_endpoint_group_id_seq'::regclass);


--
-- Name: sudoers_permission id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.sudoers_permission ALTER COLUMN id SET DEFAULT nextval('did.sudoers_permission_id_seq'::regclass);


--
-- Name: system_log_entries id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.system_log_entries ALTER COLUMN id SET DEFAULT nextval('did.system_log_entries_id_seq'::regclass);


--
-- Name: tenant_setup id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.tenant_setup ALTER COLUMN id SET DEFAULT nextval('did.tenant_setup_id_seq'::regclass);


--
-- Name: tenant_vault_config id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.tenant_vault_config ALTER COLUMN id SET DEFAULT nextval('did.tenant_vault_config_id_seq'::regclass);


--
-- Name: tenants id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.tenants ALTER COLUMN id SET DEFAULT nextval('did.tenants_id_seq'::regclass);


--
-- Name: transactions id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.transactions ALTER COLUMN id SET DEFAULT nextval('did.transactions_id_seq'::regclass);


--
-- Name: trusted_attributes id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.trusted_attributes ALTER COLUMN id SET DEFAULT nextval('did.trusted_attributes_id_seq'::regclass);


--
-- Name: user_app user_app_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_app ALTER COLUMN user_app_id SET DEFAULT nextval('did.user_app_user_app_id_seq'::regclass);


--
-- Name: user_auth_stats_count id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_auth_stats_count ALTER COLUMN id SET DEFAULT nextval('did.user_auth_stats_count_id_seq'::regclass);


--
-- Name: user_credential_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_credential_mapping ALTER COLUMN id SET DEFAULT nextval('did.user_credential_mapping_id_seq'::regclass);


--
-- Name: user_creds id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_creds ALTER COLUMN id SET DEFAULT nextval('did.user_creds_id_seq'::regclass);


--
-- Name: user_group group_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_group ALTER COLUMN group_id SET DEFAULT nextval('did.user_group_group_id_seq'::regclass);


--
-- Name: user_group_mapping id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_group_mapping ALTER COLUMN id SET DEFAULT nextval('did.user_group_mapping_id_seq'::regclass);


--
-- Name: user_privileges id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_privileges ALTER COLUMN id SET DEFAULT nextval('did.user_privileges_id_seq'::regclass);


--
-- Name: user_privileges user_roles_permission_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_privileges ALTER COLUMN user_roles_permission_id SET DEFAULT nextval('did.user_privileges_user_roles_permission_id_seq'::regclass);


--
-- Name: user_roles_permission id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_roles_permission ALTER COLUMN id SET DEFAULT nextval('did.user_roles_permission_id_seq'::regclass);


--
-- Name: user_verifiable_credentials id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_verifiable_credentials ALTER COLUMN id SET DEFAULT nextval('did.user_verifiable_credentials_id_seq'::regclass);


--
-- Name: user_wallet_credentials id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_wallet_credentials ALTER COLUMN id SET DEFAULT nextval('did.user_wallet_credentials_id_seq'::regclass);


--
-- Name: user_wallets id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_wallets ALTER COLUMN id SET DEFAULT nextval('did.user_wallets_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.users ALTER COLUMN user_id SET DEFAULT nextval('did.users_user_id_seq'::regclass);


--
-- Name: users_dids id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.users_dids ALTER COLUMN id SET DEFAULT nextval('did.users_dids_id_seq'::regclass);


--
-- Name: verifiable_credentials id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.verifiable_credentials ALTER COLUMN id SET DEFAULT nextval('did.verifiable_credentials_id_seq'::regclass);


--
-- Name: verifier_dids id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.verifier_dids ALTER COLUMN id SET DEFAULT nextval('did.verifier_dids_id_seq'::regclass);


--
-- Name: wallet_user_ad_mapping ad_id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.wallet_user_ad_mapping ALTER COLUMN ad_id SET DEFAULT nextval('did.wallet_user_ad_mapping_ad_id_seq'::regclass);


--
-- Name: workload_identities id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.workload_identities ALTER COLUMN id SET DEFAULT nextval('did.workload_identities_id_seq'::regclass);


--
-- Name: workload_identity_groups id; Type: DEFAULT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.workload_identity_groups ALTER COLUMN id SET DEFAULT nextval('did.workload_identity_groups_id_seq'::regclass);


--
-- Name: account_group_rels account_group_rels_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.account_group_rels
    ADD CONSTRAINT account_group_rels_pkey PRIMARY KEY (id);


--
-- Name: account_group_rels account_group_rels_service_account_id_key; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.account_group_rels
    ADD CONSTRAINT account_group_rels_service_account_id_key UNIQUE (service_account_id);


--
-- Name: active_directories active_directories_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.active_directories
    ADD CONSTRAINT active_directories_pkey PRIMARY KEY (id);


--
-- Name: active_directory active_directory_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.active_directory
    ADD CONSTRAINT active_directory_pkey PRIMARY KEY (id);


--
-- Name: ad_access_logs ad_access_logs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_access_logs
    ADD CONSTRAINT ad_access_logs_pkey PRIMARY KEY (id);


--
-- Name: ad_attributes ad_attributes_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_attributes
    ADD CONSTRAINT ad_attributes_pkey PRIMARY KEY (id);


--
-- Name: ad_gateways ad_gateways_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_gateways
    ADD CONSTRAINT ad_gateways_pkey PRIMARY KEY (id);


--
-- Name: ad_group_jobs ad_group_jobs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_group_jobs
    ADD CONSTRAINT ad_group_jobs_pkey PRIMARY KEY (id);


--
-- Name: ad_groups ad_groups_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_groups
    ADD CONSTRAINT ad_groups_pkey PRIMARY KEY (id);


--
-- Name: ad_logs_groups ad_logs_groups_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_logs_groups
    ADD CONSTRAINT ad_logs_groups_pkey PRIMARY KEY (id);


--
-- Name: ad_mfa_challenges ad_mfa_challenges_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_mfa_challenges
    ADD CONSTRAINT ad_mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: ad_mfa_enrollments ad_mfa_enrollments_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_mfa_enrollments
    ADD CONSTRAINT ad_mfa_enrollments_pkey PRIMARY KEY (id);


--
-- Name: ad_mfa_provider_config ad_mfa_provider_config_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_mfa_provider_config
    ADD CONSTRAINT ad_mfa_provider_config_pkey PRIMARY KEY (id);


--
-- Name: ad_ous ad_ous_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_ous
    ADD CONSTRAINT ad_ous_pkey PRIMARY KEY (id);


--
-- Name: ad_shadow_group_mapping ad_shadow_group_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_shadow_group_mapping
    ADD CONSTRAINT ad_shadow_group_mapping_pkey PRIMARY KEY (id);


--
-- Name: ad_user_devices ad_user_devices_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_user_devices
    ADD CONSTRAINT ad_user_devices_pkey PRIMARY KEY (id);


--
-- Name: ad_users ad_users_entra_id_key; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_users
    ADD CONSTRAINT ad_users_entra_id_key UNIQUE (entra_id);


--
-- Name: ad_users aduser_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ad_users
    ADD CONSTRAINT aduser_pkey PRIMARY KEY (id);


--
-- Name: agent_keys agent_keys_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.agent_keys
    ADD CONSTRAINT agent_keys_pkey PRIMARY KEY (id);


--
-- Name: agent_logs agent_logs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.agent_logs
    ADD CONSTRAINT agent_logs_pkey PRIMARY KEY (id);


--
-- Name: agents agents_machine_id_key; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.agents
    ADD CONSTRAINT agents_machine_id_key UNIQUE (machine_id);


--
-- Name: agents agents_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.agents
    ADD CONSTRAINT agents_pkey PRIMARY KEY (id);


--
-- Name: app_group_mapping app_group_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.app_group_mapping
    ADD CONSTRAINT app_group_mapping_pkey PRIMARY KEY (id);


--
-- Name: apps apps_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.apps
    ADD CONSTRAINT apps_pkey PRIMARY KEY (app_id);


--
-- Name: attribute_types attribute_types_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.attribute_types
    ADD CONSTRAINT attribute_types_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: auth_log_entries auth_log_entries_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.auth_log_entries
    ADD CONSTRAINT auth_log_entries_pkey PRIMARY KEY (id);


--
-- Name: auth_log auth_log_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.auth_log
    ADD CONSTRAINT auth_log_pkey PRIMARY KEY (id);


--
-- Name: auth_log auth_log_unique; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.auth_log
    ADD CONSTRAINT auth_log_unique UNIQUE (gateway_id, correlation_id, decision);


--
-- Name: auth_logs auth_logs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.auth_logs
    ADD CONSTRAINT auth_logs_pkey PRIMARY KEY (id);


--
-- Name: auth_policies auth_policies_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.auth_policies
    ADD CONSTRAINT auth_policies_pkey PRIMARY KEY (id);


--
-- Name: authentication_methods authentication_methods_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.authentication_methods
    ADD CONSTRAINT authentication_methods_pkey PRIMARY KEY (id);


--
-- Name: bc_user_details bc_user_details_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.bc_user_details
    ADD CONSTRAINT bc_user_details_pkey PRIMARY KEY (id);


--
-- Name: business_categories business_categories_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.business_categories
    ADD CONSTRAINT business_categories_pkey PRIMARY KEY (id);


--
-- Name: checkout_jobs checkout_jobs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.checkout_jobs
    ADD CONSTRAINT checkout_jobs_pkey PRIMARY KEY (id);


--
-- Name: client_apps client_apps_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.client_apps
    ADD CONSTRAINT client_apps_pkey PRIMARY KEY (id);


--
-- Name: client_details client_details_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.client_details
    ADD CONSTRAINT client_details_pkey PRIMARY KEY (id);


--
-- Name: network_devices client_ip; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.network_devices
    ADD CONSTRAINT client_ip UNIQUE (client_ip);


--
-- Name: credential_policies credential_policies_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_policies
    ADD CONSTRAINT credential_policies_pkey PRIMARY KEY (id);


--
-- Name: credential_rotation_jobs credential_rotation_jobs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_rotation_jobs
    ADD CONSTRAINT credential_rotation_jobs_pkey PRIMARY KEY (id);


--
-- Name: credential_rotation_policy credential_rotation_policy_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_rotation_policy
    ADD CONSTRAINT credential_rotation_policy_pkey PRIMARY KEY (policy_id);


--
-- Name: credential_submission_queue credential_submission_queue_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.credential_submission_queue
    ADD CONSTRAINT credential_submission_queue_pkey PRIMARY KEY (id);


--
-- Name: csv_jobs csv_jobs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.csv_jobs
    ADD CONSTRAINT csv_jobs_pkey PRIMARY KEY (id);


--
-- Name: custom_presentation_response_submission_queue custom_presentation_response_submission_queue_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.custom_presentation_response_submission_queue
    ADD CONSTRAINT custom_presentation_response_submission_queue_pkey PRIMARY KEY (id);


--
-- Name: database_job_queue database_job_queue_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.database_job_queue
    ADD CONSTRAINT database_job_queue_pkey PRIMARY KEY (id);


--
-- Name: db_hosts db_hosts_org_id_tenant_id_agent_vm_ip_host_vm_ip_key; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_hosts
    ADD CONSTRAINT db_hosts_org_id_tenant_id_agent_vm_ip_host_vm_ip_key UNIQUE (org_id, tenant_id, agent_vm_ip, host_vm_ip);


--
-- Name: db_hosts db_hosts_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.db_hosts
    ADD CONSTRAINT db_hosts_pkey PRIMARY KEY (id);


--
-- Name: destination_endpoint_group destination_endpoint_group_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.destination_endpoint_group
    ADD CONSTRAINT destination_endpoint_group_pkey PRIMARY KEY (id);


--
-- Name: destination_endpoint destination_endpoint_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.destination_endpoint
    ADD CONSTRAINT destination_endpoint_pkey PRIMARY KEY (id);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (device_id);


--
-- Name: domain domain_one_to_one_org_unit_id; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.domain
    ADD CONSTRAINT domain_one_to_one_org_unit_id UNIQUE (org_unit_id);


--
-- Name: domain domain_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.domain
    ADD CONSTRAINT domain_pkey PRIMARY KEY (domain_id);


--
-- Name: domain_tokens domain_tokens_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.domain_tokens
    ADD CONSTRAINT domain_tokens_pkey PRIMARY KEY (domain_id);


--
-- Name: domains domains_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.domains
    ADD CONSTRAINT domains_pkey PRIMARY KEY (id);


--
-- Name: endpoint_group_mapping endpoint_group_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_group_mapping
    ADD CONSTRAINT endpoint_group_mapping_pkey PRIMARY KEY (id);


--
-- Name: endpoint_groups endpoint_groups_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_groups
    ADD CONSTRAINT endpoint_groups_pkey PRIMARY KEY (id);


--
-- Name: endpoint_rules_conditions endpoint_rules_conditions_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_rules_conditions
    ADD CONSTRAINT endpoint_rules_conditions_pkey PRIMARY KEY (id);


--
-- Name: endpoint_rules_permission endpoint_rules_permission_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_rules_permission
    ADD CONSTRAINT endpoint_rules_permission_pkey PRIMARY KEY (id);


--
-- Name: endpoint_rules endpoint_rules_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.endpoint_rules
    ADD CONSTRAINT endpoint_rules_pkey PRIMARY KEY (id);


--
-- Name: entra_config entra_configs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.entra_config
    ADD CONSTRAINT entra_configs_pkey PRIMARY KEY (id);


--
-- Name: epm_machines_activity epm_machines_activity_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_machines_activity
    ADD CONSTRAINT epm_machines_activity_pkey PRIMARY KEY (id);


--
-- Name: epm_machines epm_machines_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_machines
    ADD CONSTRAINT epm_machines_pkey PRIMARY KEY (machine_id);


--
-- Name: epm_server_group_mapping epm_server_group_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_server_group_mapping
    ADD CONSTRAINT epm_server_group_mapping_pkey PRIMARY KEY (id);


--
-- Name: epm_server_group epm_server_group_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_server_group
    ADD CONSTRAINT epm_server_group_pkey PRIMARY KEY (id);


--
-- Name: epm_users_buffer epm_users_buffer_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_users_buffer
    ADD CONSTRAINT epm_users_buffer_pkey PRIMARY KEY (id);


--
-- Name: epm_users_cred_management epm_users_cred_management_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_users_cred_management
    ADD CONSTRAINT epm_users_cred_management_pkey PRIMARY KEY (id);


--
-- Name: epm_users epm_users_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.epm_users
    ADD CONSTRAINT epm_users_pkey PRIMARY KEY (id);


--
-- Name: escalate_privilege escalate_privilege_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.escalate_privilege
    ADD CONSTRAINT escalate_privilege_pkey PRIMARY KEY (id);


--
-- Name: ethereum_address ethereum_address_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.ethereum_address
    ADD CONSTRAINT ethereum_address_pkey PRIMARY KEY (id);


--
-- Name: field_mapping field_mapping_one_to_one; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.field_mapping
    ADD CONSTRAINT field_mapping_one_to_one UNIQUE (app_id);


--
-- Name: field_mapping field_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.field_mapping
    ADD CONSTRAINT field_mapping_pkey PRIMARY KEY (mapping_id);


--
-- Name: user_creds fk_one_to_one; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_creds
    ADD CONSTRAINT fk_one_to_one UNIQUE (user_id);


--
-- Name: identity_group_relations identity_group_relations_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.identity_group_relations
    ADD CONSTRAINT identity_group_relations_pkey PRIMARY KEY (id);


--
-- Name: identity_group_relations identity_group_relations_workload_identity_id_key; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.identity_group_relations
    ADD CONSTRAINT identity_group_relations_workload_identity_id_key UNIQUE (workload_identity_id);


--
-- Name: import_jobs import_jobs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.import_jobs
    ADD CONSTRAINT import_jobs_pkey PRIMARY KEY (job_id);


--
-- Name: issuer_credential_schema issuer_credential_schema_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.issuer_credential_schema
    ADD CONSTRAINT issuer_credential_schema_pkey PRIMARY KEY (id);


--
-- Name: issuer_credentials issuer_credentials_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.issuer_credentials
    ADD CONSTRAINT issuer_credentials_pkey PRIMARY KEY (id);


--
-- Name: issuer_dids issuer_dids_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.issuer_dids
    ADD CONSTRAINT issuer_dids_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: jump_server_endpoint_jobs jump_server_endpoint_jobs_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_server_endpoint_jobs
    ADD CONSTRAINT jump_server_endpoint_jobs_pkey PRIMARY KEY (id);


--
-- Name: jump_servers_connections jump_servers_connections_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_servers_connections
    ADD CONSTRAINT jump_servers_connections_pkey PRIMARY KEY (id);


--
-- Name: jump_server_recordings jump_servers_connections_recordings_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_server_recordings
    ADD CONSTRAINT jump_servers_connections_recordings_pkey PRIMARY KEY (id);


--
-- Name: jump_server jump_servers_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_server
    ADD CONSTRAINT jump_servers_pkey PRIMARY KEY (id);


--
-- Name: linux_commands linux_commands_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.linux_commands
    ADD CONSTRAINT linux_commands_pkey PRIMARY KEY (id);


--
-- Name: log_entries log_entries_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_entries
    ADD CONSTRAINT log_entries_pkey PRIMARY KEY (id);


--
-- Name: log_output_elasticsearch log_output_elasticsearch_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_elasticsearch
    ADD CONSTRAINT log_output_elasticsearch_pkey PRIMARY KEY (id);


--
-- Name: log_output_http log_output_http_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_http
    ADD CONSTRAINT log_output_http_pkey PRIMARY KEY (id);


--
-- Name: log_output_splunk log_output_setup_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_splunk
    ADD CONSTRAINT log_output_setup_pkey PRIMARY KEY (id);


--
-- Name: log_output_syslog log_output_syslog_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.log_output_syslog
    ADD CONSTRAINT log_output_syslog_pkey PRIMARY KEY (id);


--
-- Name: master_attribute_list master_attribute_list_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.master_attribute_list
    ADD CONSTRAINT master_attribute_list_pkey PRIMARY KEY (id);


--
-- Name: merkle_hash merkle_hash_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.merkle_hash
    ADD CONSTRAINT merkle_hash_pkey PRIMARY KEY (id);


--
-- Name: mfa_config mfa_config_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.mfa_config
    ADD CONSTRAINT mfa_config_pkey PRIMARY KEY (id);


--
-- Name: mfa_methods mfa_methods_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.mfa_methods
    ADD CONSTRAINT mfa_methods_pkey PRIMARY KEY (id);


--
-- Name: network_devices network_devices_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.network_devices
    ADD CONSTRAINT network_devices_pkey PRIMARY KEY (id);


--
-- Name: object_classes object_classes_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.object_classes
    ADD CONSTRAINT object_classes_pkey PRIMARY KEY (id);


--
-- Name: okta_configuration okta_configuration_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.okta_configuration
    ADD CONSTRAINT okta_configuration_pkey PRIMARY KEY (id);


--
-- Name: oktalog_entries oktalog_entries_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.oktalog_entries
    ADD CONSTRAINT oktalog_entries_pkey PRIMARY KEY (id);


--
-- Name: org_unit org_unit_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.org_unit
    ADD CONSTRAINT org_unit_pkey PRIMARY KEY (org_unit_id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: os_info os_info_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.os_info
    ADD CONSTRAINT os_info_pkey PRIMARY KEY (os_id);


--
-- Name: password_policy password_policy_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.password_policy
    ADD CONSTRAINT password_policy_pkey PRIMARY KEY (policy_id);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: jump_server_connection_endpoints pk_jsce; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.jump_server_connection_endpoints
    ADD CONSTRAINT pk_jsce PRIMARY KEY (jump_server_connection_id, instance_id);


--
-- Name: platform_ad_user_mapping platform_ad_user_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.platform_ad_user_mapping
    ADD CONSTRAINT platform_ad_user_mapping_pkey PRIMARY KEY (user_id, wallet_id, ad_user_id, epm_user_id, service_account_id, credential_id, credential_schema_id, issuer_id, policy_id, tenant_id, ou_id, verifier_id, endpoint_id, user_type);


--
-- Name: policy_credential_mapping policy_credential_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.policy_credential_mapping
    ADD CONSTRAINT policy_credential_mapping_pkey PRIMARY KEY (id);


--
-- Name: presentation_request_submission_queue presentation_request_submission_queue_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.presentation_request_submission_queue
    ADD CONSTRAINT presentation_request_submission_queue_pkey PRIMARY KEY (id);


--
-- Name: presentation_response_submission_queue presentation_response_submission_queue_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.presentation_response_submission_queue
    ADD CONSTRAINT presentation_response_submission_queue_pkey PRIMARY KEY (id);


--
-- Name: rules_condition rules_condition_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.rules_condition
    ADD CONSTRAINT rules_condition_pkey PRIMARY KEY (id);


--
-- Name: rules rules_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.rules
    ADD CONSTRAINT rules_pkey PRIMARY KEY (id);


--
-- Name: segment_attribute_values segment_attribute_values_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.segment_attribute_values
    ADD CONSTRAINT segment_attribute_values_pkey PRIMARY KEY (id);


--
-- Name: segment_attributes segment_attributes_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.segment_attributes
    ADD CONSTRAINT segment_attributes_pkey PRIMARY KEY (id);


--
-- Name: segments segments_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.segments
    ADD CONSTRAINT segments_pkey PRIMARY KEY (id);


--
-- Name: service_account_credential_mapping service_account_credential_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_account_credential_mapping
    ADD CONSTRAINT service_account_credential_mapping_pkey PRIMARY KEY (id);


--
-- Name: service_account_delegations service_account_delegations_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_account_delegations
    ADD CONSTRAINT service_account_delegations_pkey PRIMARY KEY (id);


--
-- Name: service_accounts_endpoints service_accounts_endpoints_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_accounts_endpoints
    ADD CONSTRAINT service_accounts_endpoints_pkey PRIMARY KEY (id);


--
-- Name: service_accounts service_accounts_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.service_accounts
    ADD CONSTRAINT service_accounts_pkey PRIMARY KEY (id);


--
-- Name: sid_histories sid_histories_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.sid_histories
    ADD CONSTRAINT sid_histories_pkey PRIMARY KEY (sid);


--
-- Name: source_endpoint_group source_endpoint_group_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.source_endpoint_group
    ADD CONSTRAINT source_endpoint_group_pkey PRIMARY KEY (id);


--
-- Name: source_endpoint source_endpoint_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.source_endpoint
    ADD CONSTRAINT source_endpoint_pkey PRIMARY KEY (id);


--
-- Name: sudoers_permission sudoers_permission_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.sudoers_permission
    ADD CONSTRAINT sudoers_permission_pkey PRIMARY KEY (id);


--
-- Name: system_log_entries system_log_entries_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.system_log_entries
    ADD CONSTRAINT system_log_entries_pkey PRIMARY KEY (id);


--
-- Name: tenant_setup tenant_setup_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.tenant_setup
    ADD CONSTRAINT tenant_setup_pkey PRIMARY KEY (id);


--
-- Name: tenant_vault_config tenant_vault_config_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.tenant_vault_config
    ADD CONSTRAINT tenant_vault_config_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: transactions transaction_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.transactions
    ADD CONSTRAINT transaction_pkey PRIMARY KEY (id);


--
-- Name: trusted_attributes trusted_attributes_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.trusted_attributes
    ADD CONSTRAINT trusted_attributes_pkey PRIMARY KEY (id);


--
-- Name: user_app user_app_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_app
    ADD CONSTRAINT user_app_pkey PRIMARY KEY (user_app_id);


--
-- Name: user_auth_stats_count user_auth_stats_count_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_auth_stats_count
    ADD CONSTRAINT user_auth_stats_count_pkey PRIMARY KEY (id);


--
-- Name: user_credential_mapping user_credential_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_credential_mapping
    ADD CONSTRAINT user_credential_mapping_pkey PRIMARY KEY (id);


--
-- Name: user_creds user_creds_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_creds
    ADD CONSTRAINT user_creds_pkey PRIMARY KEY (id);


--
-- Name: user_group_mapping user_group_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_group_mapping
    ADD CONSTRAINT user_group_mapping_pkey PRIMARY KEY (id);


--
-- Name: user_group user_group_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_group
    ADD CONSTRAINT user_group_pkey PRIMARY KEY (group_id);


--
-- Name: user_privileges user_privileges_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_privileges
    ADD CONSTRAINT user_privileges_pkey PRIMARY KEY (id);


--
-- Name: user_roles_permission user_roles_permission_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_roles_permission
    ADD CONSTRAINT user_roles_permission_pkey PRIMARY KEY (id);


--
-- Name: user_segment_permission user_segment_permission_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_segment_permission
    ADD CONSTRAINT user_segment_permission_pkey PRIMARY KEY (id);


--
-- Name: user_verifiable_credentials user_verifiable_credentials_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_verifiable_credentials
    ADD CONSTRAINT user_verifiable_credentials_pkey PRIMARY KEY (id);


--
-- Name: user_wallet_credentials user_wallet_credentials_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_wallet_credentials
    ADD CONSTRAINT user_wallet_credentials_pkey PRIMARY KEY (id);


--
-- Name: user_wallets user_wallets_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.user_wallets
    ADD CONSTRAINT user_wallets_pkey PRIMARY KEY (id);


--
-- Name: users_dids users_dids_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.users_dids
    ADD CONSTRAINT users_dids_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: verifiable_credentials verifiable_credentials_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.verifiable_credentials
    ADD CONSTRAINT verifiable_credentials_pkey PRIMARY KEY (id);


--
-- Name: verifier_dids verifier_dids_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.verifier_dids
    ADD CONSTRAINT verifier_dids_pkey PRIMARY KEY (id);


--
-- Name: wallet_user_ad_mapping wallet_user_ad_mapping_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.wallet_user_ad_mapping
    ADD CONSTRAINT wallet_user_ad_mapping_pkey PRIMARY KEY (ad_id);


--
-- Name: workload_identities workload_identities_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.workload_identities
    ADD CONSTRAINT workload_identities_pkey PRIMARY KEY (id);


--
-- Name: workload_identity_groups workload_identity_groups_pkey; Type: CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.workload_identity_groups
    ADD CONSTRAINT workload_identity_groups_pkey PRIMARY KEY (id);


--
-- Name: epm_user_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX epm_user_id ON did.epm_users_cred_management USING btree (epm_user_id);


--
-- Name: fk1_esgm_machine_id_epmm_machine_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX fk1_esgm_machine_id_epmm_machine_id ON did.epm_server_group_mapping USING btree (machine_id);


--
-- Name: fk1_jobs_domain_id_domains_domain_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX fk1_jobs_domain_id_domains_domain_id ON did.jobs USING btree (domain_id);


--
-- Name: fk1_sh_user_id_users_user_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX fk1_sh_user_id_users_user_id ON did.sid_histories USING btree (user_id);


--
-- Name: fk1_user_group_group_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX fk1_user_group_group_id ON did.epm_users_group_mapping USING btree (group_id);


--
-- Name: fk2_esg_id_epsgm_epm_server_group_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX fk2_esg_id_epsgm_epm_server_group_id ON did.epm_server_group_mapping USING btree (epm_server_group_id);


--
-- Name: fk2_linux_machines_linux_user_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX fk2_linux_machines_linux_user_id ON did.epm_users_group_mapping USING btree (epm_user_id);


--
-- Name: fk2_linuxmachinesmachine_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX fk2_linuxmachinesmachine_id ON did.epm_group_machine_mapping USING btree (machine_id);


--
-- Name: idx_db_hosts_agent_vm; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX idx_db_hosts_agent_vm ON did.db_hosts USING btree (agent_vm_ip);


--
-- Name: idx_db_hosts_org_tenant; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX idx_db_hosts_org_tenant ON did.db_hosts USING btree (org_id, tenant_id);


--
-- Name: idx_mfa_methods_client_enabled; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX idx_mfa_methods_client_enabled ON did.mfa_methods USING btree (client_id, enabled);


--
-- Name: idx_mfa_methods_expires; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX idx_mfa_methods_expires ON did.mfa_methods USING btree (expires_at);


--
-- Name: idx_mfa_methods_type; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX idx_mfa_methods_type ON did.mfa_methods USING btree (method_type);


--
-- Name: idx_mfa_methods_user_id; Type: INDEX; Schema: did; Owner: -
--

CREATE INDEX idx_mfa_methods_user_id ON did.mfa_methods USING btree (user_id);


--
-- Name: idx_user_method_unique; Type: INDEX; Schema: did; Owner: -
--

CREATE UNIQUE INDEX idx_user_method_unique ON did.mfa_methods USING btree (user_id, method_type);


--
-- Name: unique_client_method; Type: INDEX; Schema: did; Owner: -
--

CREATE UNIQUE INDEX unique_client_method ON did.mfa_methods USING btree (client_id, method_type);


--
-- Name: account_group_rels account_group_rels_endpoint_group_id_fkey; Type: FK CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.account_group_rels
    ADD CONSTRAINT account_group_rels_endpoint_group_id_fkey FOREIGN KEY (endpoint_group_id) REFERENCES did.endpoint_groups(id) ON DELETE CASCADE;


--
-- Name: account_group_rels account_group_rels_service_account_id_fkey; Type: FK CONSTRAINT; Schema: did; Owner: -
--

ALTER TABLE ONLY did.account_group_rels
    ADD CONSTRAINT account_group_rels_service_account_id_fkey FOREIGN KEY (service_account_id) REFERENCES did.service_accounts(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

-- ===== MIGRATIONS (appended from db-init/migrations) =====
--
-- Every file under db-init/migrations, in order, so a fresh database gets the full schema
-- from this one file. The migrations folder is still the source of truth and is still
-- replayed by did-schema-init on every `up` -- that is how EXISTING databases get new
-- changes, since postgres only runs this file on a first-boot empty volume. Each file is
-- idempotent (IF NOT EXISTS / ON CONFLICT), so the replay after this is a no-op.
--
-- Regenerate this section when a migration is added; do not edit it by hand.
--

-- The dump above empties search_path; migrations are written for the default one.
RESET search_path;

-- ----------------------------------------------------------------------------
-- 001_mfa_credentials.sql
-- ----------------------------------------------------------------------------

-- did.credentials: WebAuthn/passkey credential records for the self-service console.
--
-- Written by ClientRepository.SaveCredential and read by GetCredentialsByClientID /
-- UpdateCredentialSignCount (internal/mfa/repo/repository.go). Mirrors the GORM model
-- internal/mfa/model/credential.go.
--
-- This table was missing entirely: it is absent from db-init/01_schema.sql and the repo has
-- no AutoMigrate, so passkey registration failed on insert.
--
-- NOTE ON EXTRA COLUMNS: the five columns marked "Credential Record flags" below are NOT in
-- the GORM model. They are required regardless -- see the block comment above them. Do not
-- "tidy" the table to match the model.
--
-- client_id holds strconv.Itoa(did.users.user_id) (see webauthn_handler.go), NOT a
-- did.clients.client_id -- did.clients deliberately does not exist. There is intentionally no
-- tenant_id/org_id column: isolation comes from the per-org database, within which
-- did.users.user_id is unique (tenants are distinguished by users.domain_id).

CREATE TABLE IF NOT EXISTS did.credentials (
    id                 uuid         DEFAULT gen_random_uuid() NOT NULL,
    client_id          text         NOT NULL,
    credential_id      bytea        NOT NULL,
    public_key         bytea        NOT NULL,
    attestation_type   text         NOT NULL DEFAULT '',

    -- Credential Record flags (webauthn.CredentialFlags) + attestation format.
    --
    -- backup_eligible is load-bearing, not metadata. The library compares the STORED value
    -- against the flag the authenticator presents on every assertion and rejects the login
    -- outright when they disagree ("Backup Eligible flag inconsistency detected during login
    -- validation" -- webauthn/login.go). Every synced passkey (iCloud Keychain, Google
    -- Password Manager, Windows Hello with sync) sets BE=1 at registration and at assertion,
    -- so without these columns registration succeeds and login fails 100% of the time with a
    -- misleading error. backup_state may legitimately change between logins; backup_eligible
    -- may not.
    attestation_format text         NOT NULL DEFAULT '',
    user_present       boolean      NOT NULL DEFAULT false,
    user_verified      boolean      NOT NULL DEFAULT false,
    backup_eligible    boolean      NOT NULL DEFAULT false,
    backup_state       boolean      NOT NULL DEFAULT false,

    aaguid             uuid,
    sign_count         bigint       NOT NULL DEFAULT 0,
    transports         text[],
    created_at         timestamptz  NOT NULL DEFAULT now(),
    updated_at         timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT credentials_pkey PRIMARY KEY (id)
);

-- Enforces the model's `unique` tag on CredentialID. Required for correctness, not hygiene:
-- UpdateCredentialSignCount updates WHERE credential_id = ? and would otherwise silently
-- touch several rows. Credential IDs are <= 1023 bytes, well inside the btree limit.
CREATE UNIQUE INDEX IF NOT EXISTS credentials_credential_id_key
    ON did.credentials USING btree (credential_id);

-- Every read filters on client_id.
CREATE INDEX IF NOT EXISTS credentials_client_id_idx
    ON did.credentials USING btree (client_id);

-- Align the seeded passkey factor name with what the code and the console both expect.
--
-- provisioning.go seeded this row as name='webauthn', but FinishRegistration looks it up by
-- name='Passkey', the console dispatches on `selectedMFA === "Passkey"`, and DeletePasskey
-- filters mfa_detail='Passkey' (which is populated from this description). Newly provisioned
-- orgs get the corrected values from the seed; this statement fixes any org database created
-- before that change. No-op where the row is already correct or absent -- note the master's
-- did.mfa_config is empty, since 01_schema.sql contains no INSERTs and these rows are seeded
-- per-org at provisioning time.
-- Guarded on the table existing: this file is replayed against every database, and a bare
-- UPDATE against a missing did.mfa_config aborts the whole run under ON_ERROR_STOP=1.
DO $$
BEGIN
    IF to_regclass('did.mfa_config') IS NOT NULL THEN
        UPDATE did.mfa_config
           SET name = 'Passkey',
               description = 'Passkey'
         WHERE name = 'webauthn';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 002_mfa_devices.sql
-- ----------------------------------------------------------------------------

-- Unified push-MFA device registry.
--
-- WHY: push MFA is needed for AD/domain login AND for platform (console/SSC)
-- login, but each flow had its own device store, its own enrollment token store
-- and its own invite email:
--
--   AD        did.ad_mfa_enrollments  -> did.ad_user_devices.expo_push_token
--   platform  did.mfa_methods.method_data.enrollment_token
--                                     -> did.mfa_methods.method_data.expo_push_token
--
-- One phone therefore had to enrol twice, and when Expo reported the token dead
-- only whichever flow noticed deactivated its own copy -- the other kept pushing
-- into the void indefinitely.
--
-- WHY THESE TABLES ARE KEYED ON THE DEVICE, NOT THE USER: the two sides do not
-- share a user identity. did.ad_users (email_id / mail / user_principal_name,
-- often a non-routable UPN like user@corp.local) and did.users (email_address,
-- the console signup address) are separate tables in the same id space, and the
-- same human can legitimately have different addresses in each. Keying a shared
-- registry on user_id would be wrong and keying it on email would silently
-- create two rows again.
--
-- The physical device is the join key: the Expo push token is issued by the app
-- on the phone and is identical no matter which flow enrolled it. So
-- mfa_devices holds one row per (org, push token), and mfa_device_identities
-- links any number of identities to it. When the same phone enrols from the
-- second flow the device row already exists and only a link is added -- one
-- device, one push, and one deactivation that covers every identity.
--
-- Deep links are deliberately NOT unified here: installed apps still open
-- authnull://ad-enroll and authnull://mfa-push-enroll. Both now resolve to the
-- same token store, so the app can move to a single scheme whenever it ships
-- without a server change.
--
-- Idempotent: this file is replayed against the master and every org database on
-- every boot (see docker-compose.yml). Every statement is CREATE IF NOT EXISTS
-- or an ON CONFLICT DO NOTHING backfill.

-- ── device registry ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS did.mfa_devices (
    id             bigserial   PRIMARY KEY,
    org_id         integer     NOT NULL,
    -- push_transport is NOT cosmetic: the legacy React Native app registers Expo
    -- tokens and the Flutter app registers FCM tokens, and both are live during
    -- the transition. The sender is chosen from this column per device.
    push_transport text        NOT NULL DEFAULT 'expo',   -- 'expo' | 'fcm'
    push_token     text        NOT NULL,
    platform       text        NOT NULL DEFAULT '',
    device_name    text        NOT NULL DEFAULT '',
    -- Public half of the keypair the app generates in the Secure Enclave /
    -- Android Keystore at enrollment, base64 DER SubjectPublicKeyInfo. Used to
    -- verify approve/deny responses -- see internal/mfapush/signing.go. NULL for
    -- devices enrolled before response signing existed.
    public_key     text,
    public_key_alg text,
    is_active      boolean     NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    last_used_at   timestamptz
);

-- A token identifies a device only within its transport, so the triple is the
-- key. This is the constraint CompleteEnrollment upserts against to collapse a
-- second enrolment of the same phone onto the existing row.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_devices_org_transport_token_uq
    ON did.mfa_devices (org_id, push_transport, push_token);

-- ── identity links ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS did.mfa_device_identities (
    id            bigserial   PRIMARY KEY,
    device_id     bigint      NOT NULL REFERENCES did.mfa_devices(id) ON DELETE CASCADE,
    org_id        integer     NOT NULL,
    tenant_id     integer     NOT NULL DEFAULT 0,
    -- 'ad_user'       -> identity_id is did.ad_users.id
    -- 'platform_user' -> identity_id is did.users.user_id
    identity_kind text        NOT NULL,
    identity_id   integer     NOT NULL,
    -- Address the invite was sent to. Kept for display and for the AD challenge
    -- path, which only knows the email. NOT a join key across identity kinds.
    email         text        NOT NULL DEFAULT '',
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- One identity points at exactly one device: re-enrolling on a new phone
-- re-points the link rather than accumulating stale devices.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_device_identities_uq
    ON did.mfa_device_identities (org_id, identity_kind, identity_id);

CREATE INDEX IF NOT EXISTS mfa_device_identities_email_idx
    ON did.mfa_device_identities (org_id, lower(email));

CREATE INDEX IF NOT EXISTS mfa_device_identities_device_idx
    ON did.mfa_device_identities (device_id);

-- ── enrollment tokens ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS did.mfa_device_enrollments (
    id            bigserial   PRIMARY KEY,
    org_id        integer     NOT NULL,
    tenant_id     integer     NOT NULL DEFAULT 0,
    identity_kind text        NOT NULL,
    identity_id   integer     NOT NULL,
    email         text        NOT NULL,
    token         text        NOT NULL,
    used          boolean     NOT NULL DEFAULT false,
    expires_at    timestamptz NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS mfa_device_enrollments_token_uq
    ON did.mfa_device_enrollments (token);

CREATE INDEX IF NOT EXISTS mfa_device_enrollments_pending_idx
    ON did.mfa_device_enrollments (org_id, lower(email))
    WHERE used = false;

-- ── backfill: AD devices ───────────────────────────────────────────────────
-- Existing on-prem installs have live rows in both old stores. Both backfills
-- are ON CONFLICT DO NOTHING so replaying this file is harmless.

DO $$
BEGIN
    IF to_regclass('did.ad_user_devices') IS NULL THEN
        RAISE NOTICE '002_mfa_devices: did.ad_user_devices absent, skipping AD backfill';
        RETURN;
    END IF;

    INSERT INTO did.mfa_devices (org_id, push_transport, push_token, platform, device_name, is_active, created_at, last_used_at)
    SELECT d.org_id,
           'expo',
           d.expo_push_token,
           COALESCE(d.platform, ''),
           COALESCE(d.device_name, ''),
           d.is_active,
           COALESCE(d.created_at, now()),
           d.last_used_at
    FROM did.ad_user_devices d
    WHERE d.expo_push_token IS NOT NULL AND d.expo_push_token <> ''
    ON CONFLICT (org_id, push_transport, push_token) DO NOTHING;

    INSERT INTO did.mfa_device_identities (device_id, org_id, tenant_id, identity_kind, identity_id, email, created_at)
    SELECT nd.id,
           d.org_id,
           COALESCE(d.tenant_id, 0),
           'ad_user',
           d.user_id,
           COALESCE(d.email, ''),
           COALESCE(d.created_at, now())
    FROM did.ad_user_devices d
    JOIN did.mfa_devices nd
      ON nd.org_id = d.org_id AND nd.push_transport = 'expo' AND nd.push_token = d.expo_push_token
    WHERE d.expo_push_token IS NOT NULL AND d.expo_push_token <> ''
    ON CONFLICT (org_id, identity_kind, identity_id) DO NOTHING;
END $$;

-- ── backfill: platform devices ─────────────────────────────────────────────
-- The token lives in did.mfa_methods.method_data JSON. org_id is not on that
-- table, so it comes from did.users. Rows whose user has no org_id are skipped
-- rather than defaulted, since a wrong org would leak a push across tenants.

DO $$
BEGIN
    IF to_regclass('did.mfa_methods') IS NULL OR to_regclass('did.users') IS NULL THEN
        RAISE NOTICE '002_mfa_devices: did.mfa_methods or did.users absent, skipping platform backfill';
        RETURN;
    END IF;

    INSERT INTO did.mfa_devices (org_id, push_transport, push_token, platform, device_name, is_active, created_at, last_used_at)
    SELECT u.org_id,
           'expo',
           m.method_data->>'expo_push_token',
           COALESCE(m.method_data->>'platform', ''),
           COALESCE(m.method_data->>'device_name', ''),
           m.enabled,
           COALESCE(m.created_at, now()),
           m.last_used_at
    FROM did.mfa_methods m
    JOIN did.users u ON u.user_id = m.user_id
    WHERE m.method_type = 'push'
      AND u.org_id IS NOT NULL
      AND COALESCE(m.method_data->>'expo_push_token', '') <> ''
    ON CONFLICT (org_id, push_transport, push_token) DO NOTHING;

    INSERT INTO did.mfa_device_identities (device_id, org_id, tenant_id, identity_kind, identity_id, email, created_at)
    SELECT nd.id,
           u.org_id,
           0,
           'platform_user',
           m.user_id,
           COALESCE(u.email_address, ''),
           COALESCE(m.created_at, now())
    FROM did.mfa_methods m
    JOIN did.users u ON u.user_id = m.user_id
    JOIN did.mfa_devices nd
      ON nd.org_id = u.org_id AND nd.push_transport = 'expo' AND nd.push_token = m.method_data->>'expo_push_token'
    WHERE m.method_type = 'push'
      AND u.org_id IS NOT NULL
      AND COALESCE(m.method_data->>'expo_push_token', '') <> ''
    ON CONFLICT (org_id, identity_kind, identity_id) DO NOTHING;
END $$;

-- NOTE: the old columns are intentionally left in place. did.ad_user_devices and
-- did.mfa_methods.method_data.expo_push_token are no longer read -- the Go code
-- reads did.mfa_devices only -- but dropping them here would make this migration
-- irreversible against a running install. Retire them in a later migration once
-- the unified registry has been verified in the field.

-- ----------------------------------------------------------------------------
-- 003_ad_gateways.sql
-- ----------------------------------------------------------------------------

-- Bring did.ad_gateways up to the shape the AD gateway / DC sensor code expects, and
-- create the gateway↔domain junction table.
--
-- WHY THIS IS NEEDED: /ad/registerGateway inserts (org_id, tenant_id, gateway_id,
-- last_seen, created_at) with ON CONFLICT ON CONSTRAINT ad_gateways_unique, but the table
-- created by db-init/01_schema.sql has none of gateway_id, last_seen or that constraint.
-- So gateway registration -- the first step of the whole AD MFA flow -- fails outright.
--
-- The intended DDL already existed in internal/ad/db/migrations/{002,003,006}, but that
-- directory is applied by NOTHING (see db/README.md). Worse, 002 is written as
-- CREATE TABLE IF NOT EXISTS, so even if it were applied it would be a silent no-op
-- against the table 01_schema.sql already created. Hence ALTERs here, in
-- db-init/migrations/, which the did-schema-init pass actually replays.
--
-- Safe to run repeatedly: every statement is IF NOT EXISTS or guarded.

-- ---------------------------------------------------------------------------
-- ad_gateways: columns the code writes
-- ---------------------------------------------------------------------------
ALTER TABLE did.ad_gateways
    ADD COLUMN IF NOT EXISTS gateway_id  text,
    ADD COLUMN IF NOT EXISTS last_seen   timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS dc_hostname text,
    -- mode: 'monitor' logs without blocking, 'enforce' applies the verdict. The
    -- monitor-first rollout depends on this.
    ADD COLUMN IF NOT EXISTS mode        text NOT NULL DEFAULT 'monitor',
    -- fallback: what the sensor does when the backend is unreachable. 'allow' fails open
    -- (logins keep working, MFA is skipped), 'deny' fails closed. Defaulting to 'allow'
    -- so an outage cannot lock an entire domain out of Active Directory.
    ADD COLUMN IF NOT EXISTS fallback    text NOT NULL DEFAULT 'allow';

-- gateway_id must be NOT NULL for the unique constraint below to be meaningful. Applied
-- as a separate guarded step because ALTER ... SET NOT NULL is not idempotent and fails
-- if any row still holds a NULL.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'did' AND table_name = 'ad_gateways'
           AND column_name = 'gateway_id' AND is_nullable = 'YES'
    ) AND NOT EXISTS (
        SELECT 1 FROM did.ad_gateways WHERE gateway_id IS NULL
    ) THEN
        ALTER TABLE did.ad_gateways ALTER COLUMN gateway_id SET NOT NULL;
    END IF;
END $$;

-- The constraint named by registerGateway's ON CONFLICT clause. Without it that upsert
-- errors rather than updating last_seen on re-registration.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ad_gateways_unique') THEN
        ALTER TABLE did.ad_gateways
            ADD CONSTRAINT ad_gateways_unique UNIQUE (org_id, gateway_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ad_gateways_org_idx ON did.ad_gateways (org_id);

-- ---------------------------------------------------------------------------
-- gateway_domain_mappings: which domains a gateway serves
-- ---------------------------------------------------------------------------
-- One gateway can front several AD domains, which a single ad_gateways.domain_id cannot
-- express. domain_id is deliberately LEFT IN PLACE rather than dropped as
-- internal/ad/db/migrations/006 does: dropping a column is irreversible and the code may
-- still read it. Retire it separately once nothing does.
CREATE TABLE IF NOT EXISTS did.gateway_domain_mappings (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    gateway_id text        NOT NULL,
    domain_id  integer     NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT gateway_domain_mappings_unique UNIQUE (org_id, gateway_id, domain_id)
);

CREATE INDEX IF NOT EXISTS gateway_domain_mappings_gateway_idx
    ON did.gateway_domain_mappings (org_id, gateway_id);

-- Backfill from any pre-existing single-domain assignment.
INSERT INTO did.gateway_domain_mappings (org_id, gateway_id, domain_id)
SELECT org_id, gateway_id, domain_id
  FROM did.ad_gateways
 WHERE gateway_id IS NOT NULL AND domain_id IS NOT NULL
ON CONFLICT ON CONSTRAINT gateway_domain_mappings_unique DO NOTHING;

-- ----------------------------------------------------------------------------
-- 004_ad_enforcement_mode.sql
-- ----------------------------------------------------------------------------

-- Per-domain enforcement settings for the AD Shield DC sensor.
--
-- WHY THESE LIVE ON active_directories AND NOT ad_gateways:
-- The DC sensor never identifies itself by gateway. sensor.yml carries tenant_id, org_id and
-- ad_sync_domain_id (= active_directories.id) and nothing else; SensorConfig.cs has no
-- GatewayId property at all, so the gateway_id key present in the sensor.yml template is
-- silently dropped by its YAML deserialiser (IgnoreUnmatchedProperties). ad_gateways and
-- gateway_domain_mappings belong to the RADIUS bridge / proxy deployment, which is a
-- different install path with a different config file (buildGatewayConfigs).
--
-- Enforcement mode is therefore a property of the AD domain being protected, exactly as the
-- sync scope is -- see the comment on ActiveDirectory.SyncFilterGroups in
-- internal/ad/models/models.go: "stored here because the scope is a property of the
-- directory, not the gateway". Same reasoning, same table.
--
-- Before this, buildSensorConfig hardcoded mode and fallback_action, so an admin could only
-- move a domain from monitor to enforce by hand-editing sensor.yml on every DC.
--
-- Safe to run repeatedly: every statement is IF NOT EXISTS.

ALTER TABLE did.active_directories
    -- 'monitor' logs auth events and never blocks; 'enforce' applies the MFA verdict.
    -- Defaults to monitor so a newly registered domain cannot block logins before the admin
    -- has explicitly opted in. This is the monitor-first rollout Silverfort also uses.
    ADD COLUMN IF NOT EXISTS enforcement_mode text NOT NULL DEFAULT 'monitor',

    -- What the sensor does when it cannot reach this backend: 'allow' fails open (logins
    -- continue, MFA is skipped), 'deny' fails closed (authentication is refused).
    --
    -- Defaults to 'allow'. The sensor's own default is also allow, and SensorConfig.cs
    -- documents it as "availability-first, recommended for DCs" -- a fail-closed default
    -- means one backend outage refuses authentication for an entire Active Directory
    -- domain. Note this changes the effective default: the old hardcoded generator emitted
    -- fallback_action: "deny".
    ADD COLUMN IF NOT EXISTS fallback_action  text NOT NULL DEFAULT 'allow';

-- Reject anything the sensor cannot parse. SensorConfig.cs compares these as plain strings
-- with no validation, so a typo ("Monitor", "block") silently reads as not-monitor /
-- not-allow and flips the domain to enforcing and failing closed -- the exact opposite of
-- what was intended, with no error anywhere.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'active_directories_enforcement_mode_check') THEN
        ALTER TABLE did.active_directories
            ADD CONSTRAINT active_directories_enforcement_mode_check
            CHECK (enforcement_mode IN ('monitor', 'enforce'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'active_directories_fallback_action_check') THEN
        ALTER TABLE did.active_directories
            ADD CONSTRAINT active_directories_fallback_action_check
            CHECK (fallback_action IN ('allow', 'deny'));
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 005_mfa_device_selfservice.sql
-- ----------------------------------------------------------------------------

-- Device self-service for the AuthNull Authenticator: the columns the app's Home,
-- Account Details and Settings screens read and write, plus the stable key identity
-- its signed API calls authenticate with.
--
-- Extends did.mfa_devices / did.mfa_device_identities from 002_mfa_devices.sql.
--
-- Numbered 005 because 003 and 004 are taken (003_ad_gateways, 004_ad_enforcement_mode).
-- The loop in docker-compose.yml replays every file in this directory against the master
-- AND every org database on each boot, so a duplicate number would either lose a file in
-- a merge or apply two different things under one name.
--
-- Safe to run repeatedly: every statement is IF NOT EXISTS or guarded.

-- ---------------------------------------------------------------------------
-- did.mfa_devices
-- ---------------------------------------------------------------------------
ALTER TABLE did.mfa_devices
    -- key_id: lowercase hex sha256 over the raw DER SPKI of public_key. This is what
    -- the device presents to authenticate a self-service call.
    --
    -- Keyed on the KEY, not the push token or the device id, deliberately:
    --   * push tokens rotate, so authenticating pushToken/refresh with the push token
    --     would need the old token to authorise replacing that same token -- which
    --     fails exactly when it is needed, after the OS has already rotated it;
    --   * device ids are sequential per org, so they are enumerable and leak fleet size.
    -- A key id is stable across app reinstall, 256-bit, and derivable in SQL below.
    ADD COLUMN IF NOT EXISTS key_id text NOT NULL DEFAULT '',

    -- A SECOND keypair whose keystore ACL demands user verification
    -- (kSecAccessControlBiometryCurrentSet / setUserAuthenticationRequired(true)).
    -- The device physically cannot sign with it unless Face ID / fingerprint succeeded,
    -- which is what makes "require biometric" an assurance rather than a client-side
    -- preference. A self-reported uv=1 flag proves nothing: a repackaged APK sets it
    -- without ever prompting.
    ADD COLUMN IF NOT EXISTS biometric_public_key text,
    ADD COLUMN IF NOT EXISTS biometric_key_id text NOT NULL DEFAULT '',

    -- Device-wide push kill switch, distinct from the per-account toggle below.
    ADD COLUMN IF NOT EXISTS push_enabled boolean NOT NULL DEFAULT true,

    -- Reported at enrollment and on refresh; the only way to tell a stale app build
    -- from a server-side problem when a device stops responding.
    ADD COLUMN IF NOT EXISTS app_version text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS os_version text NOT NULL DEFAULT '',

    -- Separate from last_used_at: distinguishes "the OS rotated the token" from "this
    -- device answered a challenge", which are different diagnoses when push stops.
    ADD COLUMN IF NOT EXISTS token_updated_at timestamptz,
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Backfill key_id from any key already on record.
--
-- Wrapped and guarded because decode() raises on malformed base64: without this a single
-- bad row would abort the whole file, and since the loop applies it to every org database
-- one broken tenant would block the migration for all of them. Devices that fail to
-- decode keep key_id = '' and simply cannot use the self-service API until re-enrolled.
DO $$
BEGIN
    UPDATE did.mfa_devices
       SET key_id = encode(sha256(decode(public_key, 'base64')), 'hex')
     WHERE key_id = ''
       AND public_key IS NOT NULL
       AND public_key <> '';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'mfa_devices.key_id backfill skipped: %', SQLERRM;
END $$;

-- Partial index: legacy rows and any row whose key failed to decode all hold '', and
-- must not collide with each other on it. A plain unique index would reject the second
-- keyless device in an org.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_devices_org_keyid_uq
    ON did.mfa_devices (org_id, key_id) WHERE key_id <> '';

-- ---------------------------------------------------------------------------
-- did.mfa_device_identities
-- ---------------------------------------------------------------------------
-- One phone can answer for several identities (an AD account and a console account,
-- or several orgs). These preferences are per identity, not per device, because the
-- app's Account Details screen is per account.
ALTER TABLE did.mfa_device_identities
    -- Per-account push toggle. NOTE: with the Codes tab client-side only there is no
    -- fallback factor, so turning this off genuinely disables MFA for that account on
    -- this device. The challenge path reports push_disabled rather than
    -- no_device_registered so the login surface can say something true.
    ADD COLUMN IF NOT EXISTS push_enabled boolean NOT NULL DEFAULT true,

    -- Enforced server-side against biometric_public_key above. A client-side-only
    -- version of this flag would have no security value whatsoever.
    ADD COLUMN IF NOT EXISTS require_biometric boolean NOT NULL DEFAULT false,

    -- User-chosen label for this account in the app.
    ADD COLUMN IF NOT EXISTS display_name text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Deliberately NO sort_order column. Home-screen ordering spans organisations and each
-- org lives in its own database, so a per-org integer cannot express a global order.
-- Ordering stays client-side.

-- Serves the app's account list, which is always scoped to one device.
CREATE INDEX IF NOT EXISTS mfa_device_identities_device_push_idx
    ON did.mfa_device_identities (device_id, push_enabled);

-- ----------------------------------------------------------------------------
-- 006_mfa_push_activity.sql
-- ----------------------------------------------------------------------------

-- Unified push-MFA activity: one row per challenge across both flows, for the app's
-- Activity tab, the admin audit trail, and the risk-scoring lookback.
--
-- This is a MIRROR, not authoritative state. AD challenge status stays in
-- did.ad_mfa_challenges and platform status stays in Redis; neither moves. Anything that
-- must be correct reads the authoritative store — this table is for history, which those
-- two cannot provide: Redis challenges evaporate after 90 seconds, and the AD table has no
-- source IP, resource or geo.
--
-- Numbered 006: 001-005 are taken.
-- Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.mfa_push_activity (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    tenant_id  integer     NOT NULL DEFAULT 0,

    -- 'ad' | 'platform'. The two flows key their challenges differently (a sequential
    -- integer vs a UUID), so challenge_ref is text and the pair is what identifies a row.
    flow          text NOT NULL,
    challenge_ref text NOT NULL,

    -- Who was challenged. email is the account the push went to; ad_user is the AD
    -- principal the gateway named, which can differ from it.
    email         text    NOT NULL DEFAULT '',
    identity_kind text    NOT NULL DEFAULT '',
    identity_id   integer NOT NULL DEFAULT 0,
    device_id     bigint,
    ad_user       text    NOT NULL DEFAULT '',

    -- What was being accessed, derived from the SPN / destination the gateway sent.
    resource_name text NOT NULL DEFAULT '',
    resource_type text NOT NULL DEFAULT '',
    resource_id   text NOT NULL DEFAULT '',
    protocol      text NOT NULL DEFAULT '',

    binding_message text NOT NULL DEFAULT '',
    gateway_id      text NOT NULL DEFAULT '',
    session_id      text NOT NULL DEFAULT '',

    -- text, not inet: every access is an equality comparison, and '' is not a valid inet
    -- so an unknown IP would need a NULL and a three-way condition everywhere.
    client_ip text NOT NULL DEFAULT '',

    geo_city         text NOT NULL DEFAULT '',
    geo_region       text NOT NULL DEFAULT '',
    geo_country      text NOT NULL DEFAULT '',
    geo_country_code text NOT NULL DEFAULT '',
    geo_lat          double precision,
    geo_lon          double precision,
    -- 'private' | 'cache' | 'mmdb' | 'api' | '' — so a missing location can be told apart
    -- from a location that resolved to nothing.
    geo_source text NOT NULL DEFAULT '',

    risk_level text NOT NULL DEFAULT '',
    -- jsonb so tuning the rule set never needs a schema change.
    risk_reasons jsonb,

    provider       text NOT NULL DEFAULT '',
    push_transport text NOT NULL DEFAULT '',
    push_error     text NOT NULL DEFAULT '',

    -- pending | approved | denied | expired, matching the existing vocabulary.
    status text NOT NULL DEFAULT 'pending',
    -- 'device' | 'provider_poll' | 'ttl' — how the verdict was reached, which is the
    -- difference between "the user denied it" and "nobody answered".
    resolution_source text NOT NULL DEFAULT '',

    -- sha256 of the token the pushed device must present to read this challenge's full
    -- context. Only the hash is stored: a leaked table must not grant read access.
    fetch_token_sha256 text NOT NULL DEFAULT '',

    -- Set when a fraud alert has been sent, which is also the cooldown claim.
    alerted_at timestamptz,

    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz,
    responded_at timestamptz
);

-- Idempotent writes: the AD gateway polls every ~5s and both flows can retry, so Create
-- uses ON CONFLICT DO NOTHING against this.
CREATE UNIQUE INDEX IF NOT EXISTS mfa_push_activity_challenge_uq
    ON did.mfa_push_activity (org_id, flow, challenge_ref);

-- Activity tab, and the risk lookback.
CREATE INDEX IF NOT EXISTS mfa_push_activity_email_idx
    ON did.mfa_push_activity (org_id, lower(email), created_at DESC);

-- The app's own history, scoped to one device.
CREATE INDEX IF NOT EXISTS mfa_push_activity_device_idx
    ON did.mfa_push_activity (device_id, created_at DESC) WHERE device_id IS NOT NULL;

-- Serves the "have we seen this IP / country approved before" risk rules without scanning
-- a user's whole history.
CREATE INDEX IF NOT EXISTS mfa_push_activity_approved_origin_idx
    ON did.mfa_push_activity (org_id, lower(email), client_ip, geo_country_code)
    WHERE status = 'approved';

-- The sweeper's reap query. Both flows only expire a challenge when someone polls, so a
-- crashed gateway otherwise leaves rows pending forever and the Activity tab lies.
CREATE INDEX IF NOT EXISTS mfa_push_activity_pending_idx
    ON did.mfa_push_activity (expires_at) WHERE status = 'pending';

-- Retention purge.
CREATE INDEX IF NOT EXISTS mfa_push_activity_created_idx
    ON did.mfa_push_activity (created_at);

-- ----------------------------------------------------------------------------
-- 007_schema_reconciliation.sql
-- ----------------------------------------------------------------------------

-- Reconcile the live schema with what the code expects.
--
-- WHY THIS FILE EXISTS
--
-- Four directories under internal/*/db/migrations hold 21 SQL files that nothing has ever
-- replayed -- there is no migration runner that reads them. Only this directory executes, via
-- the loop at docker-compose.yml:144-165, which applies every file here to the master database
-- and to every org database on each boot.
--
-- Some of those 21 were applied by hand to individual org databases and never transcribed.
-- The result is schema drift in both directions: the alpha org database has objects the master
-- does not, the master has objects alpha does not, and several objects exist in neither while
-- the code that needs them is deployed and mounted. A newly created organisation gets whatever
-- 01_schema.sql plus this directory produces -- so anything only ever hand-applied is simply
-- absent for every future tenant.
--
-- WHY THE FILES WERE NOT JUST MOVED HERE
--
-- Tried, and it fails. Relocating them was verified against both live databases inside a
-- transaction and aborted twice:
--
--   * did.gateway_domain_mappings' migration INSERTs from did.ad_gateways.gateway_id and then
--     DROPs did.ad_gateways.domain_id. Master has no gateway_id, so the INSERT fails there; and
--     on a second pass the DROP has already removed the column the INSERT selects, so it is not
--     re-runnable at all -- which this directory requires, since every file is replayed on
--     every boot.
--   * did.db_hosts' migration is CREATE TABLE IF NOT EXISTS followed by an INSERT naming
--     hostgroup_id. db_hosts already exists on alpha WITHOUT that column, so the CREATE
--     no-oped and the INSERT failed.
--
-- That is the general trap: CREATE TABLE IF NOT EXISTS is idempotent but NOT convergent. When
-- the table already exists in a different shape -- because 01_schema.sql created its own
-- version independently -- the migration silently does nothing and every later statement that
-- depends on its columns fails.
--
-- So this file carries only ADD COLUMN / CREATE TABLE for objects PROVEN missing by querying
-- information_schema on both live databases. No data backfills, no DROP COLUMN, nothing whose
-- correctness depends on the order it ran in relative to 01_schema.sql. Shapes for tables that
-- already exist on alpha are taken from alpha's live definition, because what is running today
-- is a better source of truth than a file written against a different starting schema.
--
-- Every statement is IF NOT EXISTS. Re-running this file must always be a no-op.

-- ---------------------------------------------------------------------------
-- 1. did.auth_logs -- the decision log that has never recorded a row
-- ---------------------------------------------------------------------------
-- THIS IS THE IMPORTANT ONE. policy/repo/auth_decision_repository.go LogAuthDecision writes
-- decision, policy_id, policy_name, match_reason, session_id and mfa_outcome. None of those
-- columns exist, so every insert fails and did.auth_logs holds 0 rows in every database while
-- did.auth_log (singular, a different table) holds the sensor's own events. That is why the
-- policy decision log has always looked empty.
--
-- challenge_id is uuid to match the original migration, but note that ad_mfa_challenges.id is
-- a bigserial -- ad_challenge_id below is the column that actually links a decision to its
-- challenge. challenge_id is kept only because ListAuthDecisions selects it.
ALTER TABLE did.auth_logs
    ADD COLUMN IF NOT EXISTS policy_id        uuid,
    ADD COLUMN IF NOT EXISTS policy_name      text,
    ADD COLUMN IF NOT EXISTS match_reason     text,
    ADD COLUMN IF NOT EXISTS decision         text,
    ADD COLUMN IF NOT EXISTS mfa_outcome      text,
    ADD COLUMN IF NOT EXISTS challenge_id     uuid,
    ADD COLUMN IF NOT EXISTS session_id       text,
    -- Present on alpha, absent on master: monitor-mode context.
    ADD COLUMN IF NOT EXISTS applied_decision text,
    ADD COLUMN IF NOT EXISTS enforcement_mode text,
    ADD COLUMN IF NOT EXISTS ad_challenge_id  bigint;

-- Serves the correlation lookup in ad/src/repository/challenge_context.go, which finds the
-- decision row that caused a challenge, and the decision list in the console.
CREATE INDEX IF NOT EXISTS auth_logs_org_ts_idx
    ON did.auth_logs (org_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS auth_logs_challenge_idx
    ON did.auth_logs (org_id, ad_challenge_id) WHERE ad_challenge_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. did.blocked_principals -- table missing, endpoints mounted
-- ---------------------------------------------------------------------------
-- /ad/BlockPrincipal, /ad/UnblockPrincipal and /ad/GetBlockedPrincipals are all registered in
-- internal/ad/routes.go and this table exists in no database, so all three fail.
CREATE TABLE IF NOT EXISTS did.blocked_principals (
    id          bigserial    PRIMARY KEY,
    tenant_id   int          NOT NULL,
    org_id      int          NOT NULL,
    principal   text         NOT NULL,   -- always stored lowercase (sAMAccountName)
    domain      text         NOT NULL,   -- always stored lowercase FQDN, e.g. "test.lab"
    reason      text         NOT NULL DEFAULT '',
    blocked_by  text         NOT NULL DEFAULT '',
    blocked_at  timestamptz  NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, principal, domain)
);

CREATE INDEX IF NOT EXISTS blocked_principals_lookup_idx
    ON did.blocked_principals (org_id, domain, principal);

-- ---------------------------------------------------------------------------
-- 3. did.gateway_auth_events -- absent everywhere
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS did.gateway_auth_events (
    id                  bigserial   PRIMARY KEY,
    org_id              integer     NOT NULL,
    tenant_id           integer     NOT NULL,
    gateway_id          text        NOT NULL,
    correlation_id      text        NOT NULL,
    protocol            text        NOT NULL,
    principal           text        NOT NULL,
    realm               text        NOT NULL,
    service_spn         text        NOT NULL DEFAULT '',
    client_ip           text        NOT NULL,
    decision            text        NOT NULL,
    reason              text        NOT NULL DEFAULT '',
    upstream_error_code integer     NOT NULL DEFAULT 0,
    challenge_id        text        NOT NULL DEFAULT '',
    ts_unix_ms          bigint      NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gae_org_ts_idx      ON did.gateway_auth_events (org_id, ts_unix_ms DESC);
CREATE INDEX IF NOT EXISTS gae_correlation_idx ON did.gateway_auth_events (org_id, correlation_id);

-- ---------------------------------------------------------------------------
-- 4. Tables alpha has and master does not
-- ---------------------------------------------------------------------------
-- Shapes copied from alpha's live definition. Without these, a NEW organisation's database is
-- created without them and AD policy matching fails for that tenant while working on alpha --
-- the failure mode that is hardest to diagnose, because the feature demonstrably works.

-- Nested group membership, for AD group policy matching.
CREATE TABLE IF NOT EXISTS did.ad_group_nesting (
    child_group_id  integer     NOT NULL,
    parent_group_id integer     NOT NULL,
    ad_id           bigint,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (child_group_id, parent_group_id)
);

CREATE INDEX IF NOT EXISTS ad_group_nesting_parent_idx ON did.ad_group_nesting (parent_group_id);

-- Audit of who was added to or removed from an enrolled set.
CREATE TABLE IF NOT EXISTS did.enrolled_set_changes (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    tenant_id  integer     NOT NULL,
    action     text        NOT NULL,
    logoname   text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS enrolled_set_changes_org_idx
    ON did.enrolled_set_changes (org_id, tenant_id, created_at DESC);

-- Gateway-to-domain junction. Deliberately WITHOUT the original migration's INSERT backfill
-- and its DROP of ad_gateways.domain_id: that pair is what made the file non-re-runnable, and
-- alpha still carries domain_id today, so dropping it now would break whatever still reads it.
CREATE TABLE IF NOT EXISTS did.gateway_domain_mappings (
    id         bigserial   PRIMARY KEY,
    org_id     integer     NOT NULL,
    gateway_id text        NOT NULL,
    domain_id  integer     NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (gateway_id, domain_id)
);

CREATE INDEX IF NOT EXISTS gdm_gateway_idx ON did.gateway_domain_mappings (gateway_id);
CREATE INDEX IF NOT EXISTS gdm_domain_idx  ON did.gateway_domain_mappings (domain_id);

-- ---------------------------------------------------------------------------
-- 5. did.ad_gateways -- columns alpha has and master does not
-- ---------------------------------------------------------------------------
-- gateway_id and last_seen carry DEFAULTs even though alpha declares them NOT NULL without
-- one: adding a NOT NULL column to a table that already has rows requires a default, and
-- master's ad_gateways may not be empty.
ALTER TABLE did.ad_gateways
    ADD COLUMN IF NOT EXISTS gateway_id  text        NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS last_seen   timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS dc_hostname text,
    ADD COLUMN IF NOT EXISTS mode        text        NOT NULL DEFAULT 'monitor',
    ADD COLUMN IF NOT EXISTS fallback    text        NOT NULL DEFAULT 'allow';

-- ---------------------------------------------------------------------------
-- 6. did.ad_groups -- group discovery hints, absent everywhere
-- ---------------------------------------------------------------------------
ALTER TABLE did.ad_groups
    ADD COLUMN IF NOT EXISTS is_privileged_hint bool NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS member_count       int  NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 7. Multi-host database support -- columns absent everywhere
-- ---------------------------------------------------------------------------
-- The tables exist; these columns do not. As with everything above, the backfill that the
-- original migration paired with them is omitted: it INSERTed into did.db_hosts naming
-- hostgroup_id, which is precisely the column that was missing, so it could never have run.
-- Populating these is an application concern, not a boot-loop one.
ALTER TABLE did.db_hosts
    ADD COLUMN IF NOT EXISTS hostgroup_id INT;

ALTER TABLE did.db_synchronization
    ADD COLUMN IF NOT EXISTS host_id      INT,
    ADD COLUMN IF NOT EXISTS hostgroup_id INT,
    ADD COLUMN IF NOT EXISTS agent_vm_ip  VARCHAR(255);

ALTER TABLE did.db_user
    ADD COLUMN IF NOT EXISTS host_id           INT,
    ADD COLUMN IF NOT EXISTS default_hostgroup INT,
    ADD COLUMN IF NOT EXISTS default_schema    VARCHAR(255);

ALTER TABLE did.database_job_queue
    ADD COLUMN IF NOT EXISTS agent_vm_ip    VARCHAR(255),
    ADD COLUMN IF NOT EXISTS host_vm_ip     VARCHAR(255),
    ADD COLUMN IF NOT EXISTS hostgroup_id   INT,
    ADD COLUMN IF NOT EXISTS default_schema VARCHAR(255);

-- ---------------------------------------------------------------------------
-- 8. Policy JSON defaults -- data, and naturally idempotent
-- ---------------------------------------------------------------------------
-- Both are plain UPDATEs whose WHERE clause stops matching once applied, so replaying them on
-- every boot is free.

-- Give every existing policy the authTypes / policyMode keys the evaluator now reads.
UPDATE did.auth_policy_json
   SET policy_json = policy_json || jsonb_build_object(
           'authTypes',  COALESCE(policy_json->'authTypes',  '["ad"]'::jsonb),
           'policyMode', COALESCE(policy_json->>'policyMode', 'online'))
 WHERE policy_json IS NOT NULL
   AND (policy_json->'authTypes' IS NULL OR policy_json->'policyMode' IS NULL);

-- Retire the "notify" action. Nothing behind it ever sent a notification -- no mail, no alert,
-- no webhook -- so a policy set to notify silently allowed. Rewriting it to allow makes the
-- stored intent match the behaviour that was already happening.
UPDATE did.auth_policy_json
   SET policy_json = jsonb_set(policy_json, '{policyFlow}', '"allow"'::jsonb),
       updated_at  = now()
 WHERE lower(policy_json->>'policyFlow') = 'notify';

-- ----------------------------------------------------------------------------
-- 008_mfa_devices_signing_keys.sql
-- ----------------------------------------------------------------------------

-- Add did.mfa_devices.public_key and .public_key_alg.
--
-- WHY THIS IS A SEPARATE FILE
--
-- 002_mfa_devices.sql already DECLARES both columns. It has declared them for a while. They do not
-- exist on the alpha org database, and they never will, because that file is
--
--     CREATE TABLE IF NOT EXISTS did.mfa_devices (...)
--
-- and the table already existed when the columns were added to the file. IF NOT EXISTS made the
-- whole statement a no-op, so the edit has been inert on every database that had already run it.
-- Nothing errored. Nothing warned. The file and the schema simply disagree, and reading the file
-- tells you the wrong thing.
--
-- That is the same trap 007 documents: CREATE TABLE IF NOT EXISTS is idempotent but NOT convergent.
-- ALTER TABLE ... ADD COLUMN IF NOT EXISTS is both, which is why the fix lives here instead of as
-- another edit to 002.
--
-- WHAT WAS BROKEN
--
-- These two columns hold the device's ECDSA public key. Without them:
--
--   * CompleteEnrollment writes public_key, so enrollment fails outright -- no device can register;
--   * VerifyRequest and VerifyResponse read device.PublicKey, so every signed call under
--     /api/v1/device/* and every challenge response fails.
--
-- In other words the entire Authenticator flow, on a database where every other table looked
-- correct. It surfaced only as a NOTICE from 005's guarded key_id backfill --
-- "column public_key does not exist" -- which is the one place anything in the system mentioned it.
--
-- Safe to run repeatedly.

ALTER TABLE did.mfa_devices
    -- base64 DER SPKI of the device's signing key, and the algorithm label ("ecdsa-p256").
    -- Nullable with no default: a legacy row genuinely has no key, and '' would be
    -- indistinguishable from one that does, which the signature paths check for explicitly.
    ADD COLUMN IF NOT EXISTS public_key     text,
    ADD COLUMN IF NOT EXISTS public_key_alg text;

-- Backfill key_id for any device that already carries a key.
--
-- 005 tried this and skipped, because public_key did not exist yet -- its EXCEPTION handler caught
-- the failure and logged a NOTICE, which is exactly why the whole file did not abort for every
-- other tenant. Now that the column exists, the backfill can actually run.
--
-- Same guard for the same reason: decode() raises on malformed base64, and this directory is
-- replayed against every org database, so one bad row must not block the file for all of them.
DO $$
BEGIN
    UPDATE did.mfa_devices
       SET key_id = encode(sha256(decode(public_key, 'base64')), 'hex')
     WHERE key_id = ''
       AND public_key IS NOT NULL
       AND public_key <> '';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'mfa_devices.key_id backfill skipped: %', SQLERRM;
END $$;

-- ----------------------------------------------------------------------------
-- 009_enrollment_provenance.sql
-- ----------------------------------------------------------------------------

-- Who minted each enrollment invite, and how.
--
-- WHY
--
-- Admin-assisted enrollment lets an org admin generate another user's QR code and hand it over --
-- the only workable path for AD users whose `mail` attribute is empty or routes nowhere, which is
-- common enough to block a rollout on its own.
--
-- But the admin necessarily SEES the token, and an enrollment token is the credential that lets a
-- device register as that user. So the admin could enroll their own phone as someone else and
-- thereafter approve that person's MFA. That is a smaller escalation than it sounds -- an org admin
-- can already trigger an invite to that user's mailbox, and can already change policy -- but it is
-- the kind of thing that must leave a record rather than being merely unlikely.
--
-- The record lives on the enrollment row itself rather than in a separate audit table, because
-- that is where the artifact is: BeginEnrollment supersedes prior invites by setting used = true
-- and never deletes them, so every invite ever minted persists with its provenance attached. A
-- separate table would need its own retention, its own join, and could drift from the thing it
-- describes.
--
-- Numbered 009: 001-008 are taken. Safe to run repeatedly.

ALTER TABLE did.mfa_device_enrollments
    -- did.users.user_id of the person who caused this invite to exist. 0 for invites minted before
    -- this column existed, and for any path with no session behind it.
    ADD COLUMN IF NOT EXISTS invited_by_user_id integer NOT NULL DEFAULT 0,

    -- How it was minted:
    --   'self'      the user generated their own QR while signed in     (no escalation possible)
    --   'admin_qr'  an admin generated it for someone else              (the case worth auditing)
    --   'email'     mailed to the user's own address                    (the token never leaves the mailbox)
    --   ''          minted before this column existed
    --
    -- Text rather than an enum: a new delivery channel should not need a type migration, and the
    -- set is validated in Go where the vocabulary already lives.
    ADD COLUMN IF NOT EXISTS invite_method text NOT NULL DEFAULT '';

-- "Show me every invite an admin generated on someone else's behalf" -- the query an auditor
-- actually runs. Partial, because admin_qr is the rare case and indexing the whole table to find
-- it would be mostly dead weight.
CREATE INDEX IF NOT EXISTS mfa_device_enrollments_admin_minted_idx
    ON did.mfa_device_enrollments (org_id, invited_by_user_id, created_at DESC)
    WHERE invite_method = 'admin_qr';

-- ----------------------------------------------------------------------------
-- 010_provider_config_column.sql
-- ----------------------------------------------------------------------------

-- Make did.ad_mfa_provider_config.config storable, and make one row per org enforceable.
--
-- WHY: SAVING A PROVIDER HAS NEVER WORKED
--
-- The column is jsonb. ProviderConfigStore.Save marshals the config to JSON and then ENCRYPTS it,
-- so the value written is AES-GCM base64(nonce||ciphertext) -- not JSON. Postgres rejects it:
--
--   INSERT INTO did.ad_mfa_provider_config (provider, config, ...)
--        VALUES ('authnull', 'eZ8/Pu7/kncyuTGI3TtzpjdJQ7xdhj8NG3+UpMiD', ...)
--   ERROR: invalid input syntax for type json (SQLSTATE 22P02)
--
-- Every attempt to select an MFA provider in the console has failed with a 500 for as long as the
-- encryption has been there, and both databases hold zero rows to prove it. The consequence is not
-- an error anybody chased: GetProviderForOrg falls back to MFA_PROVIDER when no row exists, so the
-- product kept working on the deployment default and nothing said the choice had not been saved.
--
-- That fallback is what made this invisible, and it is also why it matters. On the env default a
-- vendor provider inherits the DEPLOYMENT's credentials too (okta.go falls back to OKTA_DOMAIN /
-- OKTA_API_TOKEN), so a second tenant onboarded onto the same box has its users looked up in the
-- first tenant's Okta org.
--
-- The value is ciphertext, so the column is text. Nothing reads it with jsonb operators -- the only
-- reference anywhere is the CREATE TABLE in 01_schema.sql -- so nothing is lost by the change.
--
-- Numbered 010: 001-009 are taken. Safe to run repeatedly.

-- 1. jsonb -> text.
--
-- Guarded rather than a bare ALTER: this directory is replayed on every boot, and an unconditional
-- ALTER COLUMN TYPE rewrites the whole table each time even when the type already matches. jsonb to
-- text needs no USING clause -- Postgres renders the existing value as its text form -- and both
-- databases are empty here anyway.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'did' AND table_name = 'ad_mfa_provider_config'
           AND column_name = 'config' AND data_type <> 'text'
    ) THEN
        ALTER TABLE did.ad_mfa_provider_config ALTER COLUMN config TYPE text;
        RAISE NOTICE 'ad_mfa_provider_config.config converted to text';
    END IF;
END $$;

-- 2. One row per org.
--
-- The table's PRIMARY KEY is `id`, a bare sequence, and there is no constraint on org_id at all --
-- but every read is First() by org_id and Save is a FirstOrCreate on org_id. So two concurrent
-- saves could leave two rows for one organisation and reads would pick whichever the planner
-- returned, meaning an admin could set a provider, see it saved, and have the old one still served.
--
-- Safe to add now precisely because saving has never worked: there are no rows, so there are no
-- duplicates to reconcile first.
CREATE UNIQUE INDEX IF NOT EXISTS ad_mfa_provider_config_org_uq
    ON did.ad_mfa_provider_config (org_id);

-- ----------------------------------------------------------------------------
-- 011_user_mfa_config_unique.sql
-- ----------------------------------------------------------------------------

-- One row per (user, tenant, factor) in did.user_mfa_config.
--
-- WHY: THE LOGIN SCREEN LISTS THE SAME FACTOR TWICE AND "ADD ANOTHER METHOD" NEVER WORKS
--
-- did.user_mfa_config is the enrolment record the login screen reads (VerifyUser, and now
-- GetMFAStatus). The table was created with no primary key and no unique index, and
-- MFARepository.AddUserMFAConfig did a blind INSERT -- its duplicate check was commented
-- out. So every re-registration of a factor appended another row:
--
--   user_id | tenant_id | mfa_type | mfa_detail | status
--   ------- + --------- + -------- + ---------- + --------
--        42 |         1 |        9 | Passkey    | Active
--        42 |         1 |        9 | Passkey    | Active   <- second registration
--
-- which is why a user with one passkey sees "Passkey" and then, under "use another method",
-- Passkey again -- and why removing a factor and re-adding it left an Inactive row shadowed
-- by an Active one.
--
-- With this index the enrol path can UPSERT instead, which is also what makes Settings ->
-- MFA -> Update work: re-running setup for a factor the user already has refreshes the row
-- in place rather than adding a second one.
--
-- Numbered 011: 001-010 are taken. Safe to run repeatedly -- this directory is replayed
-- against the master and every org database on every boot.

-- 1. Collapse existing duplicates, keeping one row per (user_id, tenant_id, mfa_type).
--
-- Matched on ctid because the table has no key of its own -- that is the whole problem.
-- Preference order picks the row a login would have honoured anyway: Active first (status
-- casing is inconsistent across writers, hence lower()), then most recently touched.
DELETE FROM did.user_mfa_config d
 WHERE d.ctid <> (
       SELECT k.ctid
         FROM did.user_mfa_config k
        WHERE k.user_id   = d.user_id
          AND k.tenant_id = d.tenant_id
          AND k.mfa_type  = d.mfa_type
        ORDER BY (lower(k.status) = 'active') DESC,
                 k.updated_at DESC NULLS LAST,
                 k.created_at DESC NULLS LAST,
                 k.ctid DESC
        LIMIT 1);

-- 2. Keep it that way. AddUserMFAConfig's ON CONFLICT clause targets exactly these columns,
-- so this index is a hard dependency of the enrol path, not just hygiene.
CREATE UNIQUE INDEX IF NOT EXISTS user_mfa_config_user_tenant_factor_key
    ON did.user_mfa_config (user_id, tenant_id, mfa_type);

-- ----------------------------------------------------------------------------
-- 013_license_state.sql
-- ----------------------------------------------------------------------------

-- Trial state for the on-premise licence.
--
-- WHY
--
-- The on-premise package is downloaded from a public repository and installed with no involvement
-- from Authnull, so there is nothing to activate: the trial has to start itself. First boot records a
-- timestamp here, and thirty days later the console goes read-only. Enforcement -- EvaluateAuth, the
-- challenge lifecycle, the sensor -- is never affected, so a lapse costs the customer administration
-- rather than authentication. See pkg/license.
--
-- ONE ROW, ENFORCED
--
-- A licence covers the deployment, not an organisation, so the CHECK constraint pins the primary key
-- to 1. Without it, two containers booting simultaneously could each insert a row and later reads
-- would take whichever the planner returned -- meaning the trial length would depend on which row
-- won. That is the same class of bug that migration 010 fixed for ad_mfa_provider_config, and it is
-- cheaper to prevent here than to reconcile later.
--
-- MASTER DATABASE ONLY, IN INTENT
--
-- This directory is replayed against the master database AND every organisation database on each
-- boot, so the table will exist in all of them. Only the master copy is read. Harmless, and better
-- than a migration that has to know which database it is running against.
--
-- WHAT THE SIGNATURE IS FOR, AND WHAT IT IS NOT FOR
--
-- signature is an HMAC-SHA256 over the timestamp, keyed on the deployment's own ENCRYPTION_KEY. It
-- makes a casual UPDATE visible to anyone looking -- a support engineer can distinguish "somebody
-- edited this" from "this install really is 12 days old".
--
-- It is NOT an anti-tamper control and must not be treated as one. The customer owns this database.
-- They can drop the volume and reinstall, or move the clock. That is not preventable, and the usual
-- mitigations (hardware fingerprints, hidden markers, refusing to start when time goes backwards)
-- are all defeatable while breaking legitimate restores, migrations and snapshots for honest users.
-- A mismatched signature is therefore LOGGED and the stored value is honoured, because a restored
-- backup is far more likely than fraud.
--
-- Numbered 013, not 011. PR #14 landed its own 011_user_mfa_config_unique.sql concurrently, so two
-- different migrations briefly shared the number 011. The runner globs and sorts the directory with
-- no ledger, so a duplicate number is harmless at runtime -- but it makes the sequence ambiguous to
-- read and invites the next two people to collide on the same number again. Renumbered rather than
-- left to rot. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.license_state (
    id               smallint PRIMARY KEY DEFAULT 1,
    trial_started_at timestamptz NOT NULL,
    signature        text NOT NULL DEFAULT '',
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT license_state_single_row CHECK (id = 1)
);

-- The constraint is added separately for tables created before this migration existed, so a replay
-- against an older database converges rather than silently skipping it. Guarded because ADD
-- CONSTRAINT is not idempotent.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'license_state_single_row'
           AND conrelid = 'did.license_state'::regclass
    ) THEN
        ALTER TABLE did.license_state
            ADD CONSTRAINT license_state_single_row CHECK (id = 1);
        RAISE NOTICE 'license_state_single_row constraint added';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 014_license_documents.sql
-- ----------------------------------------------------------------------------

-- Uploaded licence files, in the master database.
--
-- WHY THE DATABASE AND NOT A FILE
--
-- The console lets an administrator upload their licence, and that upload has to survive:
--
--   * a container restart or image upgrade -- a container filesystem is recreated, so a licence
--     written to a path inside it disappears and the deployment looks unlicensed again;
--   * a read-only mount -- the packaged compose mounts the licence path read-only, which is correct
--     for a file an operator drops in, and unwritable by an upload handler;
--   * more than one replica -- an upload only ever reaches the container that served the request, so
--     the other replicas would still believe the licence was missing.
--
-- The database has none of those problems and is already the thing customers back up.
--
-- The file at LICENSE_FILE stays supported as the BOOTSTRAP path: an air-gapped operator can drop a
-- licence beside the compose file before first boot without touching the console. The loader prefers
-- this table and falls back to that file.
--
-- HISTORY RATHER THAN ONE ROW
--
-- Every upload inserts. The newest row wins, decided by uploaded_at, and nothing is deleted.
--
-- Deliberately not an `active` boolean: two rows both marked active is a state somebody eventually
-- reaches, and then which licence applies depends on query order. "Most recent" cannot be ambiguous.
--
-- Keeping history also makes the obvious mistake recoverable. An administrator renewing a licence can
-- upload the wrong file -- last year's, or another deployment's -- and without history that would
-- overwrite a perfectly good licence with no way back except asking Authnull to reissue.
--
-- customer, license_id and expires_at are DENORMALISED COPIES, extracted after the signature verified
-- and stored only so the console and support can read them without re-verifying. They are display
-- data. Every authorisation decision re-verifies the document itself -- see pkg/license.Verify.
--
-- Numbered 014, following 013_license_state.sql. See the note there about the 011 collision with
-- PR #14. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.license_documents (
    id          bigserial PRIMARY KEY,
    -- The signed licence exactly as uploaded. Verified before it was written, and re-verified on
    -- every read, so this column is never trusted on its own.
    document    text NOT NULL,
    license_id  text NOT NULL DEFAULT '',
    customer    text NOT NULL DEFAULT '',
    expires_at  timestamptz,
    -- did.users.user_id of the administrator who uploaded it. 0 when it arrived by any path without a
    -- session behind it.
    uploaded_by_user_id integer NOT NULL DEFAULT 0,
    uploaded_at timestamptz NOT NULL DEFAULT now()
);

-- The only read this table serves on the hot path: "give me the newest licence". Indexed so it stays
-- a single index lookup however many renewals accumulate.
CREATE INDEX IF NOT EXISTS license_documents_newest_idx
    ON did.license_documents (uploaded_at DESC);

-- ----------------------------------------------------------------------------
-- 015_user_ssh_keys.sql
-- ----------------------------------------------------------------------------

-- SSH public keys registered against a user, in each ORGANISATION database.
--
-- This table is the SSH proxy's entire notion of identity, so most of what follows is about
-- why it has to be, rather than about the columns.
--
-- WHY A KEY AND NOT THE USERNAME
--
-- The SSH protocol gives a proxy no identity channel. The username field carries the TARGET
-- (`account@host`, the CyberArk PSM convention), and everything a client asserts about itself
-- there is attacker-chosen. The only thing a client proves before a session exists is
-- possession of a private key, so possession of a private key whose public half is in this
-- table is the anchor -- the SSH counterpart to resolving an AD principal through did.ad_users.
--
-- The consequence that matters: the principal is resolved HERE and nowhere else. In particular
-- it is never taken from did.jump_servers_connections.user_id, because on a shared account like
-- `oracle` that column holds whoever last checked the account out. Pushing to that person's
-- phone for a session somebody else opened is the precise failure this design exists to
-- prevent.
--
-- A key alone still cannot authenticate. It is the first factor; the proxy chains it to a push
-- approval and refuses the session if either half is missing.
--
-- FINGERPRINT IS THE LOOKUP KEY
--
-- SHA256 in OpenSSH's own presentation -- `SHA256:` followed by unpadded standard base64,
-- exactly what ssh.FingerprintSHA256 and `ssh-keygen -lf` produce. Stored rather than derived
-- at query time so the lookup is an index hit on a connection that has not authenticated yet.
--
-- MD5 fingerprints are not accepted anywhere. They collide, and a collision here is an
-- impersonation.
--
-- WHY THE UNIQUE INDEX IS PARTIAL
--
-- Two live keys with the same fingerprint in one org would make resolution ambiguous, and the
-- only safe answer to an ambiguous identity is to refuse the connection -- so this makes the
-- state unreachable instead. It is scoped `WHERE revoked_at IS NULL` so that revoking a key and
-- registering it again later works, which is ordinary laptop-replacement housekeeping and would
-- otherwise fail against a total unique constraint with no way for an administrator to see why.
--
-- The resolver still refuses duplicates on its own rather than trusting this index, because the
-- index does not cover revoked rows and because a resolver that assumes at most one row is one
-- schema change away from silently picking an arbitrary user.
--
-- REVOCATION IS A TIMESTAMP, NOT A DELETE
--
-- last_used_at on a deleted row is gone, and after an incident the question is always "what did
-- that key reach, and when did it stop". Revoked rows are also what make re-registration of a
-- previously withdrawn key visible instead of looking like a first registration.
--
-- WHO WRITES last_used_at
--
-- The proxy, once per successful authentication, from verifiedPublicKeyCallback -- the callback
-- that runs on the key the client actually signed with. NOT from the offer callback, which fires
-- speculatively as the client's agent asks "would you take this one?" about every key it holds,
-- several times per connection, only one of which is real.
--
-- Nullable on purpose: NULL means "registered and never used", which is a different fact from
-- "used at the epoch" and is the one stale-key review actually asks about.
--
-- Numbered 015, following 014_license_documents.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.user_ssh_keys (
    id           bigserial PRIMARY KEY,

    -- Denormalised copy of the owning organisation. Every org already has its own database, so
    -- this is redundant for isolation -- it is here because did.users carries org_id too, and
    -- because it lets the unique index below say what it means without a join.
    org_id       integer NOT NULL,

    -- did.users.user_id. No foreign key: did.users has no unique constraint this could
    -- reference, and the rest of the PAM schema does not use them either (see
    -- did.jump_server_recordings). The resolver joins and refuses a key whose user has gone.
    user_id      integer NOT NULL,

    -- `SHA256:<unpadded base64>`, as ssh.FingerprintSHA256 renders it. 128 is generous: a
    -- SHA-256 fingerprint is 50 characters including the prefix.
    fingerprint  varchar(128) NOT NULL,

    -- The key in authorized_keys form, kept so an administrator can see what was registered and
    -- so the fingerprint can be recomputed if the format ever changes. Not used for matching.
    public_key   text NOT NULL,

    -- ssh-ed25519, ecdsa-sha2-nistp256, ssh-rsa, ... Display and policy only.
    key_type     varchar(64) NOT NULL DEFAULT '',

    -- Operator-supplied, e.g. "work laptop". Free text, never interpreted.
    label        varchar(255) NOT NULL DEFAULT '',

    created_at   timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- NULL until the key authenticates a session. Written only by the proxy.
    last_used_at timestamp without time zone,

    -- NULL while the key is live. Set on revocation; the row is never deleted.
    revoked_at   timestamp without time zone
);

-- The proxy's hot path: one index hit, on an unauthenticated connection, before anything else
-- happens. Partial so that revoking and re-registering the same key is possible -- see above.
CREATE UNIQUE INDEX IF NOT EXISTS user_ssh_keys_active_fingerprint_idx
    ON did.user_ssh_keys (org_id, fingerprint)
    WHERE revoked_at IS NULL;

-- Listing a user's keys in the console, and finding every key to revoke when a person leaves.
CREATE INDEX IF NOT EXISTS user_ssh_keys_user_idx
    ON did.user_ssh_keys (org_id, user_id);

-- ----------------------------------------------------------------------------
-- 016_jump_server_liveness.sql
-- ----------------------------------------------------------------------------

-- Liveness for a jump server, so the console can say whether its proxy is running.
--
-- WHY
--
-- did.jump_server describes a jump box an administrator registered: its name, its
-- addresses, which domain it serves. Nothing in it says whether the SSH proxy on that
-- box is actually up. The proxy never announced itself, so "is my proxy running?" could
-- only be answered by logging into the machine -- which is the one question a customer
-- asks about a component they deployed and cannot see.
--
-- The proxy now announces at startup and heartbeats while it runs, and these columns are
-- where that lands.
--
-- WHY last_seen_at RATHER THAN A STATUS COLUMN
--
-- status already exists on this table and means something else: it is the administrative
-- state of the jump server record, set by a person through the console. Liveness is
-- observed, not declared, and overloading one column with both would make "disabled" and
-- "not running" indistinguishable -- two conditions with completely different remedies.
--
-- A timestamp rather than a boolean for the same reason a heartbeat is not a flag:
-- whoever is looking needs to know HOW STALE the answer is. "Last seen 4 seconds ago"
-- and "last seen on Tuesday" are both "not right now", and only one of them is an
-- incident. The staleness threshold is a display decision and deliberately not encoded
-- here.
--
-- WHY THE VERSION IS RECORDED
--
-- A proxy that is running an old binary is the failure that looks like a configuration
-- problem: it connects, it authenticates, and a capability added since its build simply
-- does nothing. The RADIUS bridge has exactly this failure mode documented in its own
-- build script, where an older build sends none of the five context fields and policies
-- scoped by them silently stop applying. Recording the version makes that a question
-- somebody can answer from the console rather than by SSH-ing to the jump box.
--
-- Every column is NULLABLE, and that is deliberate: a jump server registered before this
-- migration, or one whose proxy has never started, has no honest value to put here, and
-- a default would assert something untrue. NULL last_seen_at means "never seen", which
-- is exactly right for a jump box nobody has installed the proxy on yet.

ALTER TABLE did.jump_server
    ADD COLUMN IF NOT EXISTS last_seen_at    timestamptz  NULL,
    ADD COLUMN IF NOT EXISTS proxy_version   varchar(64)  NULL,
    ADD COLUMN IF NOT EXISTS proxy_listen    varchar(128) NULL,
    ADD COLUMN IF NOT EXISTS last_seen_ip    varchar(64)  NULL;

-- Serves the console's "which proxies are live" listing, which orders by staleness.
CREATE INDEX IF NOT EXISTS jump_server_last_seen_idx
    ON did.jump_server (last_seen_at DESC NULLS LAST);

-- ----------------------------------------------------------------------------
-- 017_ssh_recordings.sql
-- ----------------------------------------------------------------------------

-- Session recordings for the SSH proxy: where a recording came from, what it is of,
-- where its bytes live, and how long it is kept.
--
-- WHY
--
-- did.jump_server_recordings was built for the Guacamole web-terminal flow, where a
-- recording belongs to a row in did.jump_servers_connections -- a provisioned credential
-- carrying an epm_user_id, a hashed_password, a protocol and a port. An SSH proxy session
-- has none of those. It has no provisioned credential at all, which is the point of the
-- design: authority is a certificate minted per session and gone in five minutes.
--
-- So an SSH recording arrives with nothing to put in jump_server_connection_id, it takes
-- the column default of 0, and the only route from a recording back to the proxy that
-- made it does not exist. "Show me what happened on this jump server" is unanswerable.
-- These columns make the recording describe itself instead of borrowing a description
-- from a connection record that no longer models anything.
--
-- WHY target_account AND target_host RATHER THAN endpoint
--
-- endpoint is a free-text string and has been used for whatever the caller had. The two
-- questions an audit actually asks are "what did this person do" and "who touched this
-- host", and the second needs the host as a column you can filter and index, not a
-- substring. They are separate columns because they are separate facts: on a shared
-- account, ten people are 'oracle' and the host is what distinguishes what they reached.
--
-- WHY storage_backend AND storage_key RATHER THAN A URL
--
-- recording_url holds a PRESIGNED S3 URL today. That is a credential with an expiry
-- stored as data: anyone who can read the API response can forward it, it goes stale, and
-- the refresh path that exists to renew it parses X-Amz-Date out of the stored string and
-- fails the whole listing when a row is not an S3 URL. It also cannot express an on-prem
-- deployment with no object store at all.
--
-- A backend plus a key says where the bytes are without granting anyone access to them.
-- Access is then authorised per request, against the caller's session, by whatever serves
-- the content -- so revoking somebody's access actually revokes it.
--
-- recording_url stays, and Guacamole rows keep using it. New SSH rows leave it empty.
--
-- WHY hmac AND size_bytes
--
-- The proxy writes an HMAC sidecar next to every recording, and sshproxy.VerifyRecording
-- already checks a file against it. Carrying the digest here is what lets the console say
-- verified / altered / no sidecar rather than asking people to trust the database.
-- size_bytes is for capacity: recordings are unbounded today and the fail-closed default
-- means a full disk on a jump box stops SSH for everyone.
--
-- WHY expires_at
--
-- There is no retention anywhere in the product. A retention control in the console with
-- nothing enforcing it would be a promise the software does not keep, so the column comes
-- before the control does.
--
-- WHY identity_method AND presence_method
--
-- The recorder currently stamps the literal string "publickey+mfa-push" into every
-- recording header. That is true today and will not always be: identity may come from a
-- verifiable credential rather than a registered key, and presence may come from a signed
-- presentation rather than an Okta push. Two small columns now mean that is a new VALUE
-- later rather than a migration against live evidence. They are also what a decision log
-- will join on when it arrives.
--
-- Everything is NULLABLE. A Guacamole row has no honest value for any of it, and a
-- default would assert something untrue about a recording that is evidence.

ALTER TABLE did.jump_server_recordings
    ADD COLUMN IF NOT EXISTS jump_server_id   integer      NULL,
    ADD COLUMN IF NOT EXISTS target_account   varchar(64)  NULL,
    ADD COLUMN IF NOT EXISTS target_host      varchar(255) NULL,
    ADD COLUMN IF NOT EXISTS storage_backend  varchar(16)  NULL,
    ADD COLUMN IF NOT EXISTS storage_key      varchar(512) NULL,
    ADD COLUMN IF NOT EXISTS hmac             varchar(64)  NULL,
    ADD COLUMN IF NOT EXISTS size_bytes       bigint       NULL,
    ADD COLUMN IF NOT EXISTS expires_at       timestamptz  NULL,
    ADD COLUMN IF NOT EXISTS identity_method  varchar(32)  NULL,
    ADD COLUMN IF NOT EXISTS presence_method  varchar(32)  NULL;

-- Backfill the Guacamole rows through the connection they were created against, so one
-- query answers "recordings for this jump server" for both flows. Rows whose connection
-- has gone, or which never had one, keep NULL -- there is no jump server to name.
UPDATE did.jump_server_recordings r
   SET jump_server_id = c.jump_server_id
  FROM did.jump_servers_connections c
 WHERE r.jump_server_connection_id = c.id
   AND r.jump_server_id IS NULL
   AND c.jump_server_id <> 0;

-- The per-proxy recordings list, newest first. session_recording_time is a varchar on
-- this table and sorts lexically; it is included so the index still serves the ORDER BY
-- the existing listing does, rather than leaving it to a sort of the whole partition.
CREATE INDEX IF NOT EXISTS jump_server_recordings_jump_server_idx
    ON did.jump_server_recordings (jump_server_id, session_recording_time DESC);

-- Filtering a proxy's recordings by which machine was reached.
CREATE INDEX IF NOT EXISTS jump_server_recordings_target_host_idx
    ON did.jump_server_recordings (jump_server_id, target_host);

-- The retention sweeper's only query: rows whose bytes are due for deletion.
CREATE INDEX IF NOT EXISTS jump_server_recordings_expires_at_idx
    ON did.jump_server_recordings (expires_at)
    WHERE expires_at IS NOT NULL;


-- ---------------------------------------------------------------------------
-- did.user_ssh_keys: two columns that are cheap now and expensive later.
-- ---------------------------------------------------------------------------
--
-- subject_did binds a registered key to a decentralised identifier, so a key can be
-- something a credential asserts rather than something an administrator typed. Nothing
-- reads it yet. It is here because adding an identity column to a key registry that is
-- already the sole source of truth for production SSH access, with rows that predate it,
-- is materially worse than adding it while the table is young.
--
-- status is the same argument for self-service enrolment. Today an administrator
-- registers every key by hand, which does not survive two hundred operators. The flow
-- that fixes it needs a key to exist in a state that grants nothing yet, and retrofitting
-- that onto live rows means every existing row needs a defensible default and every read
-- needs a filter that did not exist when it was written.
--
-- DEFAULT 'active' is correct for every row that exists: they were all registered by an
-- administrator, which is precisely what approval will mean.

ALTER TABLE did.user_ssh_keys
    ADD COLUMN IF NOT EXISTS subject_did varchar(255) NULL,
    ADD COLUMN IF NOT EXISTS status      varchar(16)  NOT NULL DEFAULT 'active';

-- Resolution must never return a key that is pending approval. The partial index matches
-- the shape the resolver filters on, so the guard stays cheap once the flow exists.
CREATE INDEX IF NOT EXISTS user_ssh_keys_pending_idx
    ON did.user_ssh_keys (org_id, status)
    WHERE status <> 'active';

-- ----------------------------------------------------------------------------
-- 018_ssh_recording_ingest.sql
-- ----------------------------------------------------------------------------

-- Makes a recording ingestible: identified by the session that produced it, deduplicated
-- on replay, and checkable against the bytes we actually received.
--
-- 017 gave a recording somewhere to put its facts -- target host, target account, storage
-- backend and key, hmac, size. What it did not give it was a NAME. Everything there
-- describes the recording; nothing identifies the session, and so nothing joins a
-- recording to the rest of the evidence.
--
-- WHY session_id
--
-- The session id is already the join key everywhere else, and it was not invented for this
-- table. The proxy stamps it into the asciicast header, sends it as requestId on the
-- decision so authn-service's audit row carries it, and puts it in the certificate's
-- KeyId -- where the TARGET's own sshd writes it to auth.log as
--
--     Accepted publickey for ubuntu ... ID authnull-sshproxy:d7bbae886dcfe00d:ubuntu
--
-- That last one is the reason this is a column and not a substring of storage_key. A
-- customer asking "your console says this happened; prove it from MY logs" is answered by
-- grepping their auth.log for the id, and an id you cannot query is an id you cannot
-- answer with. Correlating on a timestamp instead is not evidence, it is a coincidence.
--
-- Nullable, because every Guacamole row predates the concept.
--
-- WHY content_sha256 WHEN THERE IS ALREADY AN hmac
--
-- They answer different questions and neither substitutes for the other.
--
-- The hmac is the PROXY's claim, computed with SSHPROXY_HMAC_KEY, which lives on the jump
-- box and deliberately never reaches this service. It is what proves a recording was
-- produced by that proxy and not altered afterwards -- and only someone holding the key
-- can check it. That is the property worth having, and it is why the key stays there.
--
-- But it leaves this service unable to say anything at all about its own copy. A recording
-- truncated in transit, or altered in the database later, is invisible here: we would hand
-- back bytes and repeat a digest we cannot evaluate.
--
-- content_sha256 is this service's own record of what it received. It proves nothing about
-- the proxy and is not meant to -- it catches corruption between ingest and playback, which
-- is the failure this side can actually detect. Console shows both: "matches what was
-- received" from this column, "verifiable with the proxy key" from the hmac.
--
-- WHY THE UNIQUE INDEX
--
-- Ingest retries. The proxy reports after a session closes, the report is fire-and-forget
-- so that a console outage cannot fail a session, and anything fire-and-forget that is
-- worth doing at all is retried -- which means the same recording arrives twice whenever a
-- response is lost after the write. Without a constraint that is two rows for one session
-- and an audit trail that double-counts.
--
-- On (jump_server_id, storage_key) rather than session_id alone, deliberately: one SSH
-- connection can carry several channels and each is its own recording, so session ids are
-- NOT unique here. storage_key already ends in the channel number.

ALTER TABLE did.jump_server_recordings
    ADD COLUMN IF NOT EXISTS session_id     varchar(64) NULL,
    ADD COLUMN IF NOT EXISTS content_sha256 varchar(64) NULL;

-- "Show me that session", from an id someone read out of their own auth.log.
CREATE INDEX IF NOT EXISTS jump_server_recordings_session_idx
    ON did.jump_server_recordings (session_id)
    WHERE session_id IS NOT NULL;

-- Partial, so the Guacamole rows -- which have no storage_key -- are not forced into it.
CREATE UNIQUE INDEX IF NOT EXISTS jump_server_recordings_storage_idx
    ON did.jump_server_recordings (jump_server_id, storage_key)
    WHERE storage_key IS NOT NULL AND jump_server_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 019_jump_server_keys.sql
-- ----------------------------------------------------------------------------

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


--
-- PostgreSQL database dump complete
--