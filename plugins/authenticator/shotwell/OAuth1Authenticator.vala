/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017 Jens Georg <mail@jensge.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Publishing.Authenticator.Shotwell.OAuth1 {
    internal const string ENCODE_RFC_3986_EXTRA = "!*'();:@&=+$,/?%#[] \\";

    internal class Session : Publishing.RESTSupport.Session {
        private string? request_phase_token = null;
        private string? request_phase_token_secret = null;
        private string? access_phase_token = null;
        private string? access_phase_token_secret = null;
        private string? username = null;
        private string? consumer_key = null;
        private string? consumer_secret = null;

        public Session() {
            base();
        }

        public override bool is_authenticated() {
            return (access_phase_token != null && access_phase_token_secret != null &&
                    username != null);
        }

        public void authenticate_from_persistent_credentials(string token, string secret,
                string username) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;
            this.username = username;

            this.authenticated();
        }

        public void deauthenticate() {
            access_phase_token = null;
            access_phase_token_secret = null;
            username = null;
        }

        public void set_api_credentials(string consumer_key, string consumer_secret) {
            this.consumer_key = consumer_key;
            this.consumer_secret = consumer_secret;
        }

        public void sign_transaction(Publishing.RESTSupport.Transaction txn) {
            string http_method = txn.get_method().to_string();

            debug("signing transaction with parameters:");
            debug("HTTP method = " + http_method);

            Publishing.RESTSupport.Argument[] base_string_arguments = txn.get_arguments();

            Publishing.RESTSupport.Argument[] sorted_args =
                Publishing.RESTSupport.Argument.sort(base_string_arguments);

            string arguments_string = "";
            for (int i = 0; i < sorted_args.length; i++) {
                arguments_string += (sorted_args[i].key + "=" + sorted_args[i].value);
                if (i < sorted_args.length - 1)
                    arguments_string += "&";
            }

            string? signing_key = null;
            if (access_phase_token_secret != null) {
                debug("access phase token secret available; using it as signing key");

                signing_key = consumer_secret + "&" + access_phase_token_secret;
            } else if (request_phase_token_secret != null) {
                debug("request phase token secret available; using it as signing key");

                signing_key = consumer_secret + "&" + request_phase_token_secret;
            } else {
                debug("neither access phase nor request phase token secrets available; using API " +
                        "key as signing key");

                signing_key = consumer_secret + "&";
            }

            string signature_base_string = http_method + "&" + Soup.URI.encode(
                    txn.get_endpoint_url(), ENCODE_RFC_3986_EXTRA) + "&" +
                Soup.URI.encode(arguments_string, ENCODE_RFC_3986_EXTRA);

            debug("signature base string = '%s'", signature_base_string);

            debug("signing key = '%s'", signing_key);

            // compute the signature
            string signature = RESTSupport.hmac_sha1(signing_key, signature_base_string);
            signature = Soup.URI.encode(signature, ENCODE_RFC_3986_EXTRA);

            debug("signature = '%s'", signature);

            txn.add_argument("oauth_signature", signature);
        }

        public void set_request_phase_credentials(string token, string secret) {
            this.request_phase_token = token;
            this.request_phase_token_secret = secret;
        }

        public void set_access_phase_credentials(string token, string secret, string username) {
            this.access_phase_token = token;
            this.access_phase_token_secret = secret;
            this.username = username;

            authenticated();
        }

        public string get_oauth_nonce() {
            TimeVal currtime = TimeVal();
            currtime.get_current_time();

            return Checksum.compute_for_string(ChecksumType.MD5, currtime.tv_sec.to_string() +
                    currtime.tv_usec.to_string());
        }

        public string get_oauth_timestamp() {
            return GLib.get_real_time().to_string().substring(0, 10);
        }

        public string get_consumer_key() {
            assert(consumer_key != null);
            return consumer_key;
        }

        public string get_request_phase_token() {
            assert(request_phase_token != null);
            return request_phase_token;
        }

        public string get_access_phase_token() {
            assert(access_phase_token != null);
            return access_phase_token;
        }

        public string get_access_phase_token_secret() {
            assert(access_phase_token_secret != null);
            return access_phase_token_secret;
        }

        public string get_username() {
            assert(is_authenticated());
            return username;
        }
    }

    internal class Transaction : Publishing.RESTSupport.Transaction {
        public Transaction(Session session, Publishing.RESTSupport.HttpMethod method =
                Publishing.RESTSupport.HttpMethod.POST) {
            base(session, method);
            setup_arguments();
        }

        public Transaction.with_uri(Session session, string uri,
                Publishing.RESTSupport.HttpMethod method = Publishing.RESTSupport.HttpMethod.POST) {
            base.with_endpoint_url(session, uri, method);
            setup_arguments();
        }

        private void setup_arguments() {
            var session = (Session) get_parent_session();

            add_argument("oauth_nonce", session.get_oauth_nonce());
            add_argument("oauth_signature_method", "HMAC-SHA1");
            add_argument("oauth_version", "1.0");
            add_argument("oauth_timestamp", session.get_oauth_timestamp());
            add_argument("oauth_consumer_key", session.get_consumer_key());
        }


        public override void execute() throws Spit.Publishing.PublishingError {
            ((Session) get_parent_session()).sign_transaction(this);

            base.execute();
        }
    }

    internal abstract class Authenticator : GLib.Object, Spit.Publishing.Authenticator {
        protected GLib.HashTable<string, Variant> params;
        protected Session session;
        protected Spit.Publishing.PluginHost host;

        public Authenticator(string api_key, string api_secret, Spit.Publishing.PluginHost host) {
            base();
            this.host = host;

            params = new GLib.HashTable<string, Variant>(str_hash, str_equal);
            params.insert("ConsumerKey", api_key);
            params.insert("ConsumerSecret", api_secret);

            session = new Session();
            session.set_api_credentials(api_key, api_secret);
            session.authenticated.connect(on_session_authenticated);
        }

        ~Authenticator() {
            session.authenticated.disconnect(on_session_authenticated);
        }

        // Methods from Authenticator interface
        public abstract void authenticate();

        public abstract bool can_logout();

        public GLib.HashTable<string, Variant> get_authentication_parameter() {
            return this.params;
        }

        public abstract void logout ();

        public abstract void refresh();

        public void invalidate_persistent_session() {
            set_persistent_access_phase_token("");
            set_persistent_access_phase_token_secret("");
            set_persistent_access_phase_username("");
        }

        protected bool is_persistent_session_valid() {
            return (get_persistent_access_phase_username() != null &&
                    get_persistent_access_phase_token() != null &&
                    get_persistent_access_phase_token_secret() != null);
        }

        protected string? get_persistent_access_phase_username() {
            return host.get_config_string("access_phase_username", null);
        }

        protected void set_persistent_access_phase_username(string username) {
            host.set_config_string("access_phase_username", username);
        }

        protected string? get_persistent_access_phase_token() {
            return host.get_config_string("access_phase_token", null);
        }

        protected void set_persistent_access_phase_token(string token) {
            host.set_config_string("access_phase_token", token);
        }

        protected string? get_persistent_access_phase_token_secret() {
            return host.get_config_string("access_phase_token_secret", null);
        }

        protected void set_persistent_access_phase_token_secret(string secret) {
            host.set_config_string("access_phase_token_secret", secret);
        }


        protected void on_session_authenticated() {
            params.insert("AuthToken", session.get_access_phase_token());
            params.insert("AuthTokenSecret", session.get_access_phase_token_secret());
            params.insert("Username", session.get_username());

            set_persistent_access_phase_token(session.get_access_phase_token());
            set_persistent_access_phase_token_secret(session.get_access_phase_token_secret());
            set_persistent_access_phase_username(session.get_username());


            this.authenticated();
        }

    }

}