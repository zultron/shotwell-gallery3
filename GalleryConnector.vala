/* Copyright 2012-2013 Joe Sapp nixphoeni@gentoo.org
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */


static const string _VERSION = "0.1";

static const string LICENSE = """
The Gallery3Publishing module is free software; you can redistribute it
and/or modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either version 2.1
of the License, or (at your option) any later version.

The Gallery3Publishing module is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with The Gallery3Publishing module; if not, write to the Free
Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
02110-1301 USA
""";


// This module's Spit.Module
private class ShotwellPublishingGallery3 : Object, Spit.Module {
    private Spit.Pluggable[] pluggables = new Spit.Pluggable[0];

    public ShotwellPublishingGallery3(GLib.File module_file) {
        GLib.File resource_directory = module_file.get_parent();

        pluggables += new Gallery3Service(resource_directory);
    }

    public unowned string get_module_name() {
        return _("Gallery3 publishing module");
    }

    public unowned string get_version() {
        return _VERSION;
    }

    public unowned string get_id() {
        return "org.yorba.shotwell.sharing.gallery3";
    }

    public unowned Spit.Pluggable[]? get_pluggables() {
        return pluggables;
    }
}

// This entry point is required for all SPIT modules.
public Spit.Module? spit_entry_point(Spit.EntryPointParams *params) {
    params->module_spit_interface =
        Spit.negotiate_interfaces(params->host_min_spit_interface,
            params->host_max_spit_interface, Spit.CURRENT_INTERFACE);

    return (params->module_spit_interface != Spit.UNSUPPORTED_INTERFACE)
        ? new ShotwellPublishingGallery3(params->module_file) : null;
}

// The Pluggable
public class Gallery3Service : Object, Spit.Pluggable,
        Spit.Publishing.Service {
    private const string ICON_FILENAME = "gallery3.png";

    private static Gdk.Pixbuf[] icon_pixbuf_set = null;

    public Gallery3Service(GLib.File resource_directory) {
        if (icon_pixbuf_set == null)
            icon_pixbuf_set = Resources.load_icon_set(
                resource_directory.get_child(ICON_FILENAME));
    }

    public int get_pluggable_interface(int min_host_interface,
            int max_host_interface) {
        return Spit.negotiate_interfaces(min_host_interface,
            max_host_interface,
            Spit.Publishing.CURRENT_INTERFACE);
    }

    public unowned string get_id() {
        return "publishing-gallery3";
    }

    public unowned string get_pluggable_name() {
        return "Gallery3";
    }

    public void get_info(out Spit.PluggableInfo info) {
        info.authors = "Joe Sapp";
        info.copyright = "2012-2013 Joe Sapp";
        info.translators = Resources.TRANSLATORS;
        info.version = _VERSION;
        //info.website_name = WEBSITE_NAME;
        //info.website_url = WEBSITE_URL;
        info.is_license_wordwrapped = false;
        info.license = LICENSE;
        info.icons = icon_pixbuf_set;
    }

    public void activation(bool enabled) {
    }

    public Spit.Publishing.Publisher create_publisher(
            Spit.Publishing.PluginHost host) {
        return new Publishing.Gallery3.GalleryPublisher(this, host);
    }

    public Spit.Publishing.Publisher.MediaType get_supported_media() {
        return (Spit.Publishing.Publisher.MediaType.PHOTO |
            Spit.Publishing.Publisher.MediaType.VIDEO);
    }
}


namespace Publishing.Gallery3 {
private const string SERVICE_NAME = "Gallery3";
private const string SERVICE_WELCOME_MESSAGE =
    _("You are not currently logged into your Gallery.\n\nYou must have already signed up for a Gallery3 account to complete the login process.");
private const string DEFAULT_ALBUM_DIR = _("Shotwell");
private const string DEFAULT_ALBUM_TITLE =
    _("Shotwell default directory");
private const string REST_PATH = "/index.php/rest";

private class Album {

    // Properties
    public string name { get; private set; default = ""; }
    public string title { get; private set; default = ""; }
    public string summary { get; private set; default = ""; }
    public string parentname { get; private set; default = ""; }
    public string url { get; private set; default = ""; }
    public string path { get; private set; default = ""; }
    public bool editable { get; private set; default = false; }

    // Each element is a collection
    public Album(Json.Object collection) {

        unowned Json.Object entity =
            collection.get_object_member("entity");

        title = entity.get_string_member("title");
        name = entity.get_string_member("name");
        parentname = entity.get_string_member("parent");
        url = collection.get_string_member("url");
        editable = entity.get_boolean_member("can_edit");

        // Get the path from the last two elements of the URL.
        // This should always be "/item/#" where "#" is a number.
        path = strip_session_url(url);

    }

}

private class BaseGalleryTransaction :
        Publishing.RESTSupport.Transaction {

    protected Json.Parser parser;

    // BaseGalleryTransaction constructor
    public BaseGalleryTransaction(Session session, string endpoint_url,
            string item_path = "",
            Publishing.RESTSupport.HttpMethod method =
            Publishing.RESTSupport.HttpMethod.POST) {

        // TODO: eventually we can remove this
        if ((item_path != "") && (item_path[0] != '/')) {
            warning("Bad item path, this is a bug!");
            error(item_path);
        }

        base.with_endpoint_url(session,
            endpoint_url + REST_PATH + item_path,
            method);

        this.parser = new Json.Parser();

    }

    protected unowned Json.Node get_root_node()
            throws Spit.Publishing.PublishingError {

        string json_object;
        unowned Json.Node root_node;

        json_object = get_response();

        if ((null == json_object) || (0 == json_object.length))
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                "No response data from %s", get_endpoint_url());

        try {
            this.parser.load_from_data(json_object);
        }
        catch (GLib.Error e) {
            // If this didn't work, reset the "executed" state
            warning("ERROR: didn't load JSON data");
            set_is_executed(false);
            throw new Spit.Publishing.PublishingError.PROTOCOL_ERROR(e.message);
        }

        root_node = this.parser.get_root();
        if (root_node.is_null())
            throw new Spit.Publishing.PublishingError.MALFORMED_RESPONSE(
                "Root node is null, doesn't appear to be JSON data");

        return root_node;

    }

}

private class KeyFetchTransaction : BaseGalleryTransaction {

    private string key = "";

    // KeyFetchTransaction constructor
    //
    // url: Base gallery URL
    public KeyFetchTransaction(Session session, string url,
            string username, string password) {
        base(session, url);
        add_argument("user", username);
        add_argument("password", password);
    }

    public string get_key() {

        if (key != "")
            return key;

        key = get_response();

        // The returned data isn't actually a JSON object...
        if (null == key || "" == key || 0 == key.length) {
            warning("No response data from \"%s\"", get_endpoint_url());
            return "";
        }

        // Eliminate quotes surrounding key
        key = key[1:-1];

        return key;
    }

}

private class GalleryRequestTransaction : BaseGalleryTransaction {

    // GalleryRequestTransaction constructor
    //
    // item: Item URL component
    public GalleryRequestTransaction(Session session, string item,
            Publishing.RESTSupport.HttpMethod method =
            Publishing.RESTSupport.HttpMethod.GET) {

        if (!session.is_authenticated()) {
            error("Not authenticated");
        }
        else {
            base(session, session.url, item, method);
            add_header("X-Gallery-Request-Key", session.key);
            add_header("X-Gallery-Request-Method", "GET");
        }

    }

}

private class GetAlbumURLsTransaction : GalleryRequestTransaction {

    private string? session_url;

    //TODO: handle > 100 items
    public GetAlbumURLsTransaction(Session session) {

        base(session, "/item/1");
        add_argument("type", "album");
        add_argument("scope", "all");

        session_url = session.url;

    }

    public string [] get_album_urls() {

        unowned Json.Node root_node;
        unowned Json.Array all_members;

        try {
            root_node = get_root_node();
        }
        catch (Spit.Publishing.PublishingError e) {
            error("Could not get root node");
        }

        all_members =
            root_node.get_object().get_array_member("members");

        string [] member_urls = null;

        for (int i = 0; i <= all_members.get_length() - 1; i++)
            member_urls += all_members.get_string_element(i);

        return member_urls;

    }

}

private class GetAlbumsTransaction : GalleryRequestTransaction {

    //TODO: handle > 100 items
    public GetAlbumsTransaction(Session session, string [] album_urls) {

        string url_list = "";

        base(session, "/items");
        add_argument("scope", "all");

        // Wrap each URL in double quotes and separate by a comma
        for (uint i = 0; i <= album_urls.length - 1; i++)
            album_urls[i] = "\"" + album_urls[i] + "\"";
        url_list = "[" + string.joinv(",", album_urls) + "]";

        add_argument("urls", url_list);

    }

    public Album [] get_albums()
            throws Spit.Publishing.PublishingError {

        Album [] albums = null;
        Album tmp_album;
        unowned Json.Node root_node = get_root_node();
        unowned Json.Array members = root_node.get_array();

        // Only add editable items
        for (uint i = 0; i <= members.get_length() - 1; i++) {
            tmp_album = new Album(members.get_object_element(i));

            if (tmp_album.editable)
                albums += tmp_album;
            else
                warning(@"Album \"$(tmp_album.title)\" is not editable");
        }

        return albums;
    }

}

// Class to create or get a tag URL
private class GalleryGetTagTransaction : BaseGalleryTransaction {

    public GalleryGetTagTransaction(Session session, string tag_name) {

        if (!session.is_authenticated()) {
            error("Not authenticated");
        }
        else {
            Json.Generator entity = new Json.Generator();
            Json.Node root_node = new Json.Node(Json.NodeType.OBJECT);
            Json.Object obj = new Json.Object();

            base(session, session.url,
                "/tags",
                Publishing.RESTSupport.HttpMethod.POST);
            add_header("X-Gallery-Request-Key", session.key);
            add_header("X-Gallery-Request-Method", "POST");

            obj.set_string_member("name", tag_name);
            root_node.set_object(obj);
            entity.set_root(root_node);

            size_t entity_length;
            string entity_value = entity.to_data(out entity_length);

            debug("created entity: %s", entity_value);

            add_argument("entity", entity_value);
        }

    }

    public string tag_url() {

        unowned Json.Node root_node;
        string url;

        try {
            root_node = get_root_node();
        }
        catch (Spit.Publishing.PublishingError e) {
            error("Could not get root node");
        }

        url =
            root_node.get_object().get_string_member("url");

        return url;

    }

}

private class GalleryGetItemTagsURLsTransaction :
        GalleryRequestTransaction {

    private string item_tags_path = "";

    public GalleryGetItemTagsURLsTransaction(Session session,
            string item_url) {

        base(session, item_url);

    }

    public string get_item_tags_path() {

        unowned Json.Node root_node;
        unowned Json.Object relationships, tags;

        if ("" == item_tags_path) {

            try {
                root_node = get_root_node();
            }
            catch (Spit.Publishing.PublishingError e) {
                error("Could not get root node");
            }

            relationships =
                root_node.get_object().get_object_member("relationships");
            tags = relationships.get_object_member("tags");

            item_tags_path = tags.get_string_member("url");

            // Remove the session URL from the beginning of this URL
            Session session = get_parent_session() as Session;
            item_tags_path = strip_session_url(item_tags_path);

        }

        return item_tags_path;

    }

}

private class GallerySetTagRelationshipTransaction :
        BaseGalleryTransaction {

    // Properties
    public GallerySetTagRelationshipTransaction(Session session,
            string item_tags_path, string tag_url, string item_url) {

        if (!session.is_authenticated()) {
            error("Not authenticated");
        }
        else {
            Json.Generator entity = new Json.Generator();
            Json.Node root_node = new Json.Node(Json.NodeType.OBJECT);
            Json.Object obj = new Json.Object();

            base(session, session.url,
                item_tags_path,
                Publishing.RESTSupport.HttpMethod.POST);
            add_header("X-Gallery-Request-Key", session.key);
            add_header("X-Gallery-Request-Method", "POST");

            obj.set_string_member("tag", tag_url);
            obj.set_string_member("item", item_url);
            root_node.set_object(obj);
            entity.set_root(root_node);

            size_t entity_length;
            string entity_value = entity.to_data(out entity_length);

            debug("created entity: %s", entity_value);

            add_argument("entity", entity_value);
        }

    }

}

private class GalleryAlbumCreateTransaction : BaseGalleryTransaction {

    // Properties
    public PublishingParameters parameters { get; private set; }
    // Private variables
    private string? session_url;

    // GalleryAlbumCreateTransaction constructor
    //
    // parameters: New album parameters
    public GalleryAlbumCreateTransaction(Session session,
            PublishingParameters parameters) {

        if (!session.is_authenticated()) {
            error("Not authenticated");
        }
        else {
            Json.Generator entity = new Json.Generator();
            Json.Node root_node = new Json.Node(Json.NodeType.OBJECT);
            Json.Object obj = new Json.Object();

            base(session, session.url, "/item/1",
                Publishing.RESTSupport.HttpMethod.POST);
            add_header("X-Gallery-Request-Key", session.key);
            add_header("X-Gallery-Request-Method", "POST");

            this.session_url = session.url;
            this.parameters = parameters;

            obj.set_string_member("name", parameters.album_name);
            obj.set_string_member("type", "album");
            obj.set_string_member("title", parameters.album_title);
            root_node.set_object(obj);
            entity.set_root(root_node);

            string entity_value = entity.to_data(null);

            debug("created entity: %s", entity_value);

            add_argument("entity", entity_value);
        }

    }

    public string get_new_album_path() {

        unowned Json.Node root_node;
        string new_path;

        try {
            root_node = get_root_node();
        }
        catch (Spit.Publishing.PublishingError e) {
            error("Could not get root node");
        }

        new_path =
            root_node.get_object().get_string_member("url");
        new_path = strip_session_url(new_path);

        return new_path;

    }

}

private class GalleryUploadTransaction :
        Publishing.RESTSupport.UploadTransaction {

    private Session session;
    private Json.Generator generator;
    private PublishingParameters parameters;
    private string item_url;
    private string item_path;
    private string item_tags_path;

    public GalleryUploadTransaction(Session session,
            PublishingParameters parameters,
            Spit.Publishing.Publishable publishable) {

        // TODO: eventually we can remove this
        if (parameters.album_path[0] != '/') {
            warning("Bad upload item path, this is a bug!");
            error(parameters.album_path);
        }

        base.with_endpoint_url(session, publishable,
            session.url + REST_PATH + parameters.album_path);

        this.parameters = parameters;
        this.session = session;

        add_header("X-Gallery-Request-Key", session.key);
        add_header("X-Gallery-Request-Method", "POST");

        GLib.HashTable<string, string> disposition_table =
            new GLib.HashTable<string, string>(GLib.str_hash,
                                               GLib.str_equal);
        string? title = publishable.get_publishing_name();
        string filename = publishable.get_param_string(
            Spit.Publishing.Publishable.PARAM_STRING_BASENAME);
        if (title == null || title == "")
            title = filename;

        disposition_table.insert("filename", @"$(filename)");
        disposition_table.insert("name", "file");

        set_binary_disposition_table(disposition_table);

        // Do the JSON stuff
        generator = new Json.Generator();
        string type = (publishable.get_media_type() ==
            Spit.Publishing.Publisher.MediaType.VIDEO) ?
                "movie" : "photo";

        Json.Node root_node = new Json.Node(Json.NodeType.OBJECT);
        Json.Object obj = new Json.Object();
        obj.set_string_member("name", filename);
        obj.set_string_member("type", type);
        obj.set_string_member("title", title);

        root_node.set_object(obj);
        generator.set_root(root_node);

        add_argument("entity", generator.to_data(null));
    }

    private string get_new_item_url() {

        string json_object;
        string new_url;
        unowned Json.Node root_node;
        Json.Parser parser = new Json.Parser();

        json_object = get_response();

        if ((null == json_object) || (0 == json_object.length)) {
            warning("No response data from %s", get_endpoint_url());
            return "";
        }

        debug("json_object: %s", json_object);

        try {
            parser.load_from_data(json_object);
        }
        catch (GLib.Error e) {
            // If this didn't work, reset the "executed" state
            // TODO: can we recover from this?
            warning("ERROR: didn't load JSON data");
            set_is_executed(false);
            error(e.message);
        }

        root_node = parser.get_root();
        if (root_node.is_null()) {
            warning("Root node is null, doesn't appear to be JSON data");
            return "";
        }

        new_url =
            root_node.get_object().get_string_member("url");

        return new_url;

    }

    private void do_set_tag_relationship(string tag_url)
            throws Spit.Publishing.PublishingError {
        GallerySetTagRelationshipTransaction tag_txn =
            new GallerySetTagRelationshipTransaction(
                (Session) get_parent_session(), item_tags_path,
                tag_url, item_url);

        tag_txn.execute();

        debug("Response from setting tag relationship: %s",
            tag_txn.get_response());
    }

    private string get_new_item_tags_path() {
        GalleryGetItemTagsURLsTransaction tag_urls_txn =
            new GalleryGetItemTagsURLsTransaction(
                (Session) get_parent_session(), item_path);

        try {
            tag_urls_txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("Problem getting the item_tags URL: %s",
                err.message);
            return "";
        }

        return tag_urls_txn.get_item_tags_path();
    }

    private string get_tag_url(string tag) {

        GalleryGetTagTransaction tag_txn =
            new GalleryGetTagTransaction(
                (Session) get_parent_session(), tag);

        try {
            tag_txn.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("Problem getting the tags URL: %s",
                err.message);
            return "";
        }

        return tag_txn.tag_url();

    }

    private void on_upload_completed()
            throws Spit.Publishing.PublishingError {

        string[] keywords;

        debug("EVENT: upload completed, evaluating tags");

        keywords = base.publishable.get_publishing_keywords();

        // If this publishable has no tags, continue
        if (null == keywords) {
            debug("No tags");
            return;
        }

        // Get URLs from the file we just finished uploading
        item_url = get_new_item_url();
        item_path = strip_session_url(item_url);
        item_tags_path = get_new_item_tags_path();
        debug("new item path is %s", item_path);
        debug("item_tags path is %s", item_tags_path);

        // Verify these aren't empty
        if (("" == item_path) || ("" == item_tags_path)) {
            throw new
                Spit.Publishing.PublishingError.COMMUNICATION_FAILED(
                    "Could not obtain URL of uploaded item or its " +
                    "\"item_tags\" relationship URL");
        }

        // Do the tagging here
        foreach (string tag in keywords) {
            debug(@"Found tag: $(tag)");
            string new_tag_url = get_tag_url(tag);

            // Next, get the item_tags URL from the newly-created
            // item and write to it.
            try {
                do_set_tag_relationship(new_tag_url);
            } catch (Spit.Publishing.PublishingError err) {
                debug("Problem setting the relationship between tag " +
                    "and item: %s", err.message);
                throw err;
            }
        }

    }

    public override void execute()
            throws Spit.Publishing.PublishingError {
        base.execute();

        // Run tagging operations here
        on_upload_completed();
    }

}


public class GalleryPublisher : Spit.Publishing.Publisher, GLib.Object {
    private weak Spit.Publishing.PluginHost host = null;
    private Spit.Publishing.ProgressCallback progress_reporter = null;
    private weak Spit.Publishing.Service service = null;
    private Session session = null;
    private bool running = false;
    private Album[] albums = null;
    private string key = null;

    private PublishingOptionsPane publishing_options_pane = null;

    public GalleryPublisher(Spit.Publishing.Service service,
            Spit.Publishing.PluginHost host) {
        this.service = service;
        this.host = host;
        this.session = new Session();
    }

    public bool is_running() {
        return running;
    }

    public Spit.Publishing.Service get_service() {
        return service;
    }

    public void start() {
        if (is_running())
            return;

        if (host == null)
            error("GalleryPublisher: start( ): can't start; this " +
              "publisher is not restartable.");

        debug("GalleryPublisher: starting interaction.");

        running = true;

        key = get_api_key();

        if ((null == key) || ("" == key))
            do_show_service_welcome_pane();
        else {
            string url = get_gallery_url();
            string username = get_gallery_username();

            if ((null == username) || (null == key) || (null == url))
                do_show_service_welcome_pane();
            else {
                debug("ACTION: attempting network login for user " +
                    "'%s' at URL '%s' from saved credentials.",
                    username, url);

                host.install_account_fetch_wait_pane();

                session.authenticate(url, username, key);

                // Initiate an album transaction
                do_fetch_album_urls();
            }
        }
    }

    public void stop() {
        debug("GalleryPublisher: stop( ) invoked.");

        running = false;
    }

    // Config getters/setters
    // API key
    internal string? get_api_key() {
        return host.get_config_string("api-key", null);
    }

    internal void set_api_key(string key) {
        host.set_config_string("api-key", key);
    }

    // URL
    internal string? get_gallery_url() {
        return host.get_config_string("url", null);
    }

    internal void set_gallery_url(string url) {
        host.set_config_string("url", url);
    }

    // Username
    internal string? get_gallery_username() {
        return host.get_config_string("username", null);
    }

    internal void set_gallery_username(string username) {
        host.set_config_string("username", username);
    }

    internal bool? get_persistent_strip_metadata() {
        return host.get_config_bool("strip-metadata", false);
    }

    internal void set_persistent_strip_metadata(bool strip_metadata) {
        host.set_config_bool("strip-metadata", strip_metadata);
    }

    // Pane installation functions
    private void do_show_service_welcome_pane() {
        debug("ACTION: showing service welcome pane.");

        host.install_welcome_pane(SERVICE_WELCOME_MESSAGE,
          on_service_welcome_login);
    }

    private void do_show_credentials_pane(CredentialsPane.Mode mode) {
        debug("ACTION: showing credentials capture pane in %s mode.",
          mode.to_string());

        session.deauthenticate();

        CredentialsPane creds_pane =
            new CredentialsPane(host, mode, get_gallery_url(),
                get_gallery_username(), get_api_key());
        creds_pane.go_back.connect(on_credentials_go_back);
        creds_pane.login.connect(on_credentials_login);

        host.install_dialog_pane(creds_pane);
    }

    private void do_network_login(string url, string username,
            string password) {
        debug("ACTION: attempting network login for user '%s' at URL " +
            "'%s'.", username, url);

        host.install_login_wait_pane();

        KeyFetchTransaction fetch_trans =
            new KeyFetchTransaction(session, url, username, password);
        fetch_trans.network_error.connect(on_key_fetch_error);
        fetch_trans.completed.connect(on_key_fetch_complete);

        try {
            fetch_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("Caught an error attempting to login");
            // 403 errors may be recoverable, so don't post the error to
            // our host immediately; instead, try to recover from it
            on_key_fetch_error(fetch_trans, err);
        }
    }

    private void do_fetch_album_urls() {

        host.install_account_fetch_wait_pane();

        GetAlbumURLsTransaction album_trans =
            new GetAlbumURLsTransaction(session);
        album_trans.network_error.connect(on_album_urls_fetch_error);
        album_trans.completed.connect(on_album_urls_fetch_complete);

        try {
            album_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            debug("Caught an error attempting to fetch albums");
            // 403 errors may be recoverable, so don't post the error to
            // our host immediately; instead, try to recover from it
            on_album_urls_fetch_error(album_trans, err);
        }

    }

    private void do_fetch_albums(string [] album_urls) {

        GetAlbumsTransaction album_trans =
            new GetAlbumsTransaction(session, album_urls);
        album_trans.network_error.connect(on_album_fetch_error);
        album_trans.completed.connect(on_album_fetch_complete);

        try {
            album_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // 403 errors may be recoverable, so don't post the error to
            // our host immediately; instead, try to recover from it
            on_album_fetch_error(album_trans, err);
        }

    }

    private void do_show_publishing_options_pane(string url,
            string username) {

        debug("ACTION: showing publishing options pane");

        Gtk.Builder builder = new Gtk.Builder();

        try {
            builder.add_from_file(
                host.get_module_file().get_parent().get_child(
                    "gallery3_publishing_options_pane.glade").get_path());
        }
        catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is " +
                        "unavailable. Publishing to " + SERVICE_NAME +
                        " can't continue.")));
            return;
        }

        publishing_options_pane =
            new PublishingOptionsPane(host, url, username, albums,
                builder, get_persistent_strip_metadata());
        publishing_options_pane.publish.connect(
            on_publishing_options_pane_publish);
        publishing_options_pane.logout.connect(
            on_publishing_options_pane_logout);
        host.install_dialog_pane(publishing_options_pane);

    }

    private void do_create_album(PublishingParameters parameters) {

        debug("ACTION: creating album");

        GalleryAlbumCreateTransaction album_trans =
            new GalleryAlbumCreateTransaction(session, parameters);
        album_trans.network_error.connect(on_album_create_error);
        album_trans.completed.connect(on_album_create_complete);

        try {
            album_trans.execute();
        } catch (Spit.Publishing.PublishingError err) {
            // 403 errors may be recoverable, so don't post the error to
            // our host immediately; instead, try to recover from it
            on_album_create_error(album_trans, err);
        }

    }

    private void do_publish(PublishingParameters parameters) {

        debug("ACTION: publishing items");

        set_persistent_strip_metadata(parameters.strip_metadata);
        host.set_service_locked(true);
        progress_reporter =
            host.serialize_publishables(parameters.photo_major_axis_size,
                parameters.strip_metadata);

        // Serialization is a long and potentially cancellable
        // operation, so before we use the publishables, make sure that
        // the publishing interaction is still running. If it isn't, the
        // publishing environment may be partially torn down so do a
        // short-circuit return.
        if (!is_running())
            return;

        Uploader uploader =
            new Uploader(session, host.get_publishables(),
                parameters);
        uploader.upload_complete.connect(on_publish_complete);
        uploader.upload_error.connect(on_publish_error);
        uploader.upload(on_upload_status_updated);

    }

    private void do_show_success_pane() {
        debug("ACTION: showing success pane.");

        host.set_service_locked(false);
        host.install_success_pane();
    }

    // Callbacks
    private void on_service_welcome_login() {
        if (!is_running())
            return;

        debug("EVENT: user clicked 'Login' in welcome pane.");

        do_show_credentials_pane(CredentialsPane.Mode.INTRO);
    }

    private void on_credentials_login(string url, string username,
            string password) {
        if (!is_running())
            return;

        debug("EVENT: user '%s' clicked 'Login' in credentials pane.",
          username);

        set_gallery_url(url);
        set_gallery_username(username);
        do_network_login(url, username, password);
    }

    private void on_credentials_go_back() {
        if (!is_running())
            return;

        debug("EVENT: user is attempting to go back.");

        do_show_service_welcome_pane();
    }

    private void on_key_fetch_error(
            Publishing.RESTSupport.Transaction bad_txn,
            Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_key_fetch_complete);
        bad_txn.network_error.disconnect(on_key_fetch_error);

        if (!is_running())
            return;

        // ignore these events if the session is already auth'd
        if (session.is_authenticated())
            return;

        debug("EVENT: network transaction to fetch key for login " +
            "failed; response = '%s'.",
            bad_txn.get_response());

        // HTTP error 403 is invalid authentication -- if we get this
        // error during key fetch then we can just show the login screen
        // again with a retry message; if we get any error other than
        // 403 though, we can't recover from it, so just post the error
        // to the user
        if (bad_txn.get_status_code() == 403) {
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.FAILED_RETRY);
        }
        else if (bad_txn.get_status_code() == 400) {
            // This might not be a Gallery URL
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.NOT_GALLERY_URL);
        }
        else {
            host.post_error(err);
        }
    }

    private void on_key_fetch_complete(
            Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_key_fetch_complete);
        txn.network_error.disconnect(on_key_fetch_error);

        if (!is_running())
            return;

        // ignore these events if the session is already auth'd
        if (session.is_authenticated())
            return;

        key = (txn as KeyFetchTransaction).get_key();

        if (key == null) error("key doesn\'t exist");
        else {
            string url = get_gallery_url();
            string username = get_gallery_username();

            debug("EVENT: network transaction to fetch key completed " +
                  "successfully (%s).", key);

            set_api_key(key);
            session.authenticate(url, username, key);

            // Initiate an album transaction
            do_fetch_album_urls();
        }
    }

    private void on_album_urls_fetch_error(
            Publishing.RESTSupport.Transaction bad_txn,
            Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_album_urls_fetch_complete);
        bad_txn.network_error.disconnect(on_album_urls_fetch_error);

        if (!is_running())
            return;

        // ignore these events if the session is not auth'd
        if (!session.is_authenticated())
            return;

        debug("EVENT: network transaction to fetch album URLs " +
            "failed; response = \'%s\'.",
            bad_txn.get_response());

        // HTTP error 403 is invalid authentication -- if we get this
        // error during key fetch then we can just show the login screen
        // again with a retry message; if we get any error other than
        // 403 though, we can't recover from it, so just post the error
        // to the user
        if (bad_txn.get_status_code() == 403) {
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.FAILED_RETRY);
        }
        else if (bad_txn.get_status_code() == 400) {
            // This might not be a Gallery URL
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.NOT_GALLERY_URL);
        }
        else {
            host.post_error(err);
        }
    }

    private void on_album_urls_fetch_complete(
            Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_album_urls_fetch_complete);
        txn.network_error.disconnect(on_album_urls_fetch_error);

        if (!is_running())
            return;

        // ignore these events if the session is not auth'd
        if (!session.is_authenticated())
            return;

        debug("EVENT: user has retrieved all album URLs.");

        string [] album_urls =
            (txn as GetAlbumURLsTransaction).get_album_urls();

        do_fetch_albums(album_urls);
    }

    private void on_album_fetch_error(
            Publishing.RESTSupport.Transaction bad_txn,
            Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_album_fetch_complete);
        bad_txn.network_error.disconnect(on_album_fetch_error);

        if (!is_running())
            return;

        // ignore these events if the session is not auth'd
        if (!session.is_authenticated())
            return;

        debug("EVENT: network transaction to fetch albums " +
            "failed; response = \'%s\'.",
            bad_txn.get_response());

        // HTTP error 403 is invalid authentication -- if we get this
        // error during key fetch then we can just show the login screen
        // again with a retry message; if we get any error other than
        // 403 though, we can't recover from it, so just post the error
        // to the user
        if (bad_txn.get_status_code() == 403) {
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.FAILED_RETRY);
        }
        else if (bad_txn.get_status_code() == 400) {
            // This might not be a Gallery URL
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.NOT_GALLERY_URL);
        }
        else {
            host.post_error(err);
        }
    }

    private void on_album_fetch_complete(
            Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_album_fetch_complete);
        txn.network_error.disconnect(on_album_fetch_error);

        if (!is_running())
            return;

        // ignore these events if the session is not auth'd
        if (!session.is_authenticated())
            return;

        debug("EVENT: user is attempting to populate the album list.");

        albums = (txn as GetAlbumsTransaction).get_albums();

        string url = session.url;
        string username = session.username;

        do_show_publishing_options_pane(url, username);
    }

    private void on_album_create_error(
            Publishing.RESTSupport.Transaction bad_txn,
            Spit.Publishing.PublishingError err) {
        bad_txn.completed.disconnect(on_album_create_complete);
        bad_txn.network_error.disconnect(on_album_create_error);

        if (!is_running())
            return;

        // ignore these events if the session is not auth'd
        if (!session.is_authenticated())
            return;

        debug("EVENT: network transaction to create an album " +
            "failed; response = \'%s\'.",
            bad_txn.get_response());

        // HTTP error 403 is invalid authentication -- if we get this
        // error during key fetch then we can just show the login screen
        // again with a retry message; if we get any error other than
        // 403 though, we can't recover from it, so just post the error
        // to the user
        if (bad_txn.get_status_code() == 403) {
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.FAILED_RETRY);
        }
        else if (bad_txn.get_status_code() == 400) {
            // This might not be a Gallery URL
            // TODO: can we give more detail on the problem?
            do_show_credentials_pane(CredentialsPane.Mode.NOT_GALLERY_URL);
        }
        else {
            host.post_error(err);
        }
    }

    private void on_album_create_complete(
            Publishing.RESTSupport.Transaction txn) {
        txn.completed.disconnect(on_album_create_complete);
        txn.network_error.disconnect(on_album_create_error);

        if (!is_running())
            return;

        // ignore these events if the session is not auth'd
        if (!session.is_authenticated())
            return;

        PublishingParameters new_params =
            (txn as GalleryAlbumCreateTransaction).parameters;
        new_params.album_path =
            (txn as GalleryAlbumCreateTransaction).get_new_album_path();

        debug("EVENT: user has created an album at \"%s\".",
            new_params.album_path);

        do_publish(new_params);
    }

    private void on_publish_error(
            Publishing.RESTSupport.BatchUploader uploader,
            Spit.Publishing.PublishingError err) {
        if (!is_running())
            return;

        debug("EVENT: uploader reports upload error = '%s'.", err.message);

        uploader.upload_complete.disconnect(on_publish_complete);
        uploader.upload_error.disconnect(on_publish_error);

        host.post_error(err);
    }

    private void on_upload_status_updated(int file_number,
        double completed_fraction) {

        if (!is_running())
            return;

        debug("EVENT: uploader reports upload %.2f percent complete.",
            100.0 * completed_fraction);

        assert(progress_reporter != null);

        progress_reporter(file_number, completed_fraction);

    }

    private void on_publish_complete(
            Publishing.RESTSupport.BatchUploader uploader,
            int num_published) {
        uploader.upload_complete.disconnect(on_publish_complete);
        uploader.upload_error.disconnect(on_publish_error);

        if (!is_running())
            return;

        // ignore these events if the session is not auth'd
        if (!session.is_authenticated())
            return;

        debug("EVENT: publishing complete; %d items published",
            num_published);

        do_show_success_pane();

    }

    private void on_publishing_options_pane_logout() {
        publishing_options_pane.publish.disconnect(
            on_publishing_options_pane_publish);
        publishing_options_pane.logout.disconnect(
            on_publishing_options_pane_logout);

        if (!is_running())
            return;

        debug("EVENT: user is attempting to log out.");

        session.deauthenticate();
        do_show_service_welcome_pane();
    }

    private void on_publishing_options_pane_publish(PublishingParameters parameters, bool strip_metadata) {
        publishing_options_pane.publish.disconnect(
            on_publishing_options_pane_publish);
        publishing_options_pane.logout.disconnect(
            on_publishing_options_pane_logout);

        if (!is_running())
            return;

        debug("EVENT: user is attempting to publish something.");

        parameters.strip_metadata = strip_metadata;

        if (parameters.is_to_new_album()) {
            debug("EVENT: must create new album \"%s\" first.",
                parameters.album_name);
            do_create_album(parameters);
        }
        else {
            do_publish(parameters);
        }
    }

}

internal class PublishingOptionsPane : Spit.Publishing.DialogPane, GLib.Object {
    private const string DEFAULT_ALBUM_NAME = "";
    private const string LAST_ALBUM_CONFIG_KEY = "last-album";

    private Gtk.Builder builder = null;

    private Gtk.Grid pane_widget = null;
    private Gtk.Label title_label = null;
    private Gtk.RadioButton use_existing_radio = null;
    private Gtk.ComboBoxText existing_albums_combo = null;
    private Gtk.RadioButton create_new_radio = null;
    private Gtk.Entry new_album_entry = null;
    private Gtk.CheckButton strip_metadata_check = null;
    private Gtk.Button publish_button = null;
    private Gtk.Button logout_button = null;

    private Album[] albums;
    private weak Spit.Publishing.PluginHost host;

    public signal void publish(PublishingParameters parameters,
        bool strip_metadata);
    public signal void logout();

    public PublishingOptionsPane(Spit.Publishing.PluginHost host,
            string url, string username, Album[] albums,
            Gtk.Builder builder, bool strip_metadata) {
        this.albums = albums;
        this.host = host;

        this.builder = builder;
        assert(null != builder);
        assert(builder.get_objects().length() > 0);

        // pull in all widgets from builder
        pane_widget = builder.get_object("pane_widget") as Gtk.Grid;
        title_label = builder.get_object("title_label") as Gtk.Label;
        use_existing_radio = builder.get_object("publish_to_existing_radio") as Gtk.RadioButton;
        existing_albums_combo = builder.get_object("existing_albums_combo") as Gtk.ComboBoxText;
        create_new_radio = builder.get_object("publish_new_radio") as Gtk.RadioButton;
        new_album_entry = builder.get_object("new_album_name") as Gtk.Entry;
        strip_metadata_check = this.builder.get_object("strip_metadata_check") as Gtk.CheckButton;
        publish_button = builder.get_object("publish_button") as Gtk.Button;
        logout_button = builder.get_object("logout_button") as Gtk.Button;

        // populate any widgets whose contents are
        // programmatically-generated
        title_label.set_label(
            _("Publishing to %s as %s.").printf(url, username));
        strip_metadata_check.set_active(strip_metadata);

        // connect all signals
        use_existing_radio.clicked.connect(on_use_existing_radio_clicked);
        create_new_radio.clicked.connect(on_create_new_radio_clicked);
        new_album_entry.changed.connect(on_new_album_entry_changed);
        logout_button.clicked.connect(on_logout_clicked);
        publish_button.clicked.connect(on_publish_clicked);
    }

    private void on_publish_clicked() {
        string album_name;
        if (create_new_radio.get_active()) {
            album_name = new_album_entry.get_text();
            host.set_config_string(LAST_ALBUM_CONFIG_KEY, album_name);
            PublishingParameters param =
                new PublishingParameters.to_new_album(album_name);
            debug("Trying to publish to \"%s\"", album_name);
            publish(param,
                strip_metadata_check.get_active());
        } else {
            album_name =
                albums[existing_albums_combo.get_active()].title;
            host.set_config_string(LAST_ALBUM_CONFIG_KEY, album_name);
            string album_path =
                albums[existing_albums_combo.get_active()].path;
            publish(new PublishingParameters.to_existing_album(album_path),
                strip_metadata_check.get_active());
        }
    }

    private void on_use_existing_radio_clicked() {
        existing_albums_combo.set_sensitive(true);
        new_album_entry.set_sensitive(false);
        existing_albums_combo.grab_focus();
        update_publish_button_sensitivity();
    }

    private void on_create_new_radio_clicked() {
        new_album_entry.set_sensitive(true);
        existing_albums_combo.set_sensitive(false);
        new_album_entry.grab_focus();
        update_publish_button_sensitivity();
    }

    private void on_logout_clicked() {
        logout();
    }

    private void update_publish_button_sensitivity() {
        string album_name = new_album_entry.get_text();
        publish_button.set_sensitive(!(album_name.strip() == "" &&
            create_new_radio.get_active()));
    }

    private void on_new_album_entry_changed() {
        update_publish_button_sensitivity();
    }

    public void installed() {
        int default_album_id = -1;
        string last_album =
            host.get_config_string(LAST_ALBUM_CONFIG_KEY, "");
        for (int i = 0; i < albums.length; i++) {
            existing_albums_combo.append_text(albums[i].title);
            if ((albums[i].title == last_album) ||
                ((DEFAULT_ALBUM_NAME == albums[i].title) &&
                    (-1 == default_album_id)))
                default_album_id = i;
        }

        if (albums.length == 0) {
            existing_albums_combo.set_sensitive(false);
            use_existing_radio.set_sensitive(false);
            create_new_radio.set_active(true);
            new_album_entry.grab_focus();
            new_album_entry.set_text(DEFAULT_ALBUM_NAME);
        } else {
            if (default_album_id >= 0) {
                use_existing_radio.set_active(true);
                existing_albums_combo.set_active(default_album_id);
                new_album_entry.set_sensitive(false);
            } else {
                create_new_radio.set_active(true);
                existing_albums_combo.set_active(0);
                new_album_entry.set_text(DEFAULT_ALBUM_NAME);
                new_album_entry.grab_focus();
            }
        }
        update_publish_button_sensitivity();
    }

    protected void notify_publish(PublishingParameters parameters) {
        publish(parameters, strip_metadata_check.get_active());
    }

    protected void notify_logout() {
        logout();
    }

    public Gtk.Widget get_widget() {
        return pane_widget;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        installed();
    }

    public void on_pane_uninstalled() {
    }
}

internal class PublishingParameters {

    // Private variables for properties
    private string _album_title = "";

    // Properties
    public string album_title {
        get {
            assert(is_to_new_album());
            return _album_title;
        }
        private set { _album_title = value; }
    }
    public string album_name { get; private set; default = ""; }
    public string album_path { get; set; default = ""; }
    public string entity_title { get; private set; default = ""; }
    public int photo_major_axis_size { get; private set; default = 0; }
    public bool strip_metadata { get; set; default = false; }

    private PublishingParameters() {
    }

    public PublishingParameters.to_new_album(string album_title) {
        this.album_name = album_title.delimit(" ", '-');
        //this.album_name = this.album_name.delimit("\"\'", '');
        this.album_title = album_title;
    }

    public PublishingParameters.to_existing_album(string album_path) {
        this.album_path = album_path;
    }

    public bool is_to_new_album() {
        return (album_name != "");
    }

    // converts a publish-to-new-album parameters object into a publish-to-existing-album
    // parameters object
    public void convert() {
        assert(is_to_new_album());

        album_name = "";
    }
}

internal class CredentialsPane : Spit.Publishing.DialogPane, GLib.Object {
    public enum Mode {
        INTRO,
        FAILED_RETRY,
        NOT_GALLERY_URL;

        public string to_string() {
            switch (this) {
                case Mode.INTRO:
                    return "INTRO";

                case Mode.FAILED_RETRY:
                    return "FAILED_RETRY";

                case Mode.NOT_GALLERY_URL:
                    return "NOT_GALLERY_URL";

                default:
                    error("unrecognized CredentialsPane.Mode enumeration value");
            }
        }
    }

    private CredentialsGrid frame = null;
    private Gtk.Widget grid_widget = null;

    public signal void go_back();
    public signal void login(string url, string uname, string password,
        string key);

    public CredentialsPane(Spit.Publishing.PluginHost host,
            Mode mode = Mode.INTRO,
            string? url = null, string? username = null,
            string? key = null) {

        Gtk.Builder builder = new Gtk.Builder();

        try {
            builder.add_from_file(
                host.get_module_file().get_parent().get_child(
                    "gallery3_authentication_pane.glade").get_path());
        }
        catch (Error e) {
            warning("Could not parse UI file! Error: %s.", e.message);
            host.post_error(
                new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    _("A file required for publishing is " +
                        "unavailable. Publishing to " + SERVICE_NAME +
                        " can't continue.")));
            return;
        }

        frame = new CredentialsGrid(host, mode, url, username, key, builder);
        grid_widget = frame.pane_widget as Gtk.Widget;
    }

    protected void notify_go_back() {
        go_back();
    }

    protected void notify_login(string url, string uname,
            string password, string key) {
        login(url, uname, password, key);
    }

    public Gtk.Widget get_widget() {
        assert(null != grid_widget);
        return grid_widget;
    }

    public Spit.Publishing.DialogPane.GeometryOptions get_preferred_geometry() {
        return Spit.Publishing.DialogPane.GeometryOptions.NONE;
    }

    public void on_pane_installed() {
        frame.go_back.connect(notify_go_back);
        frame.login.connect(notify_login);

        frame.installed();
    }

    public void on_pane_uninstalled() {
        frame.go_back.disconnect(notify_go_back);
        frame.login.disconnect(notify_login);
    }
}

internal class CredentialsGrid : GLib.Object {
    private const string INTRO_MESSAGE = _("Enter the URL for your Gallery3 site and the username and password (or API key) for your Gallery3 account.");
    private const string FAILED_RETRY_MESSAGE = _("The username and password or API key were incorrect. To try again, re-enter your username and password below.");
    private const string NOT_GALLERY_URL_MESSAGE = _("The URL entered does not appear to be the main directory of a Gallery3 instance. Please make sure you typed it correctly and it does not have any trailing components (e.g., index.php).");

    private weak Spit.Publishing.PluginHost host = null;
    private Gtk.Builder builder = null;
    public Gtk.Grid pane_widget { get; private set; default = null; }
    private Gtk.Label intro_message_label = null;
    private Gtk.Entry url_entry = null;
    private Gtk.Entry username_entry = null;
    private Gtk.Entry password_entry = null;
    private Gtk.Entry key_entry = null;
    private Gtk.Button login_button = null;
    private Gtk.Button go_back_button = null;
    private string? url = null;
    private string? username = null;
    private string? key = null;

    public signal void go_back();
    public signal void login(string url, string username,
        string password, string key);

    public CredentialsGrid(Spit.Publishing.PluginHost host,
            CredentialsPane.Mode mode = CredentialsPane.Mode.INTRO,
            string? url = null, string? username = null,
            string? key = null,
            Gtk.Builder builder) {
        this.host = host;
        this.url = url;
        this.key = key;
        this.username = username;

        this.builder = builder;
        assert(builder != null);
        assert(builder.get_objects().length() > 0);

        // pull in all widgets from builder
        pane_widget = builder.get_object("gallery3_auth_pane_widget") as Gtk.Grid;
        intro_message_label = builder.get_object("intro_message_label") as Gtk.Label;
        url_entry = builder.get_object("url_entry") as Gtk.Entry;
        username_entry = builder.get_object("username_entry") as Gtk.Entry;
        key_entry = builder.get_object("key_entry") as Gtk.Entry;
        password_entry = builder.get_object("password_entry") as Gtk.Entry;
        go_back_button = builder.get_object("go_back_button") as Gtk.Button;
        login_button = builder.get_object("login_button") as Gtk.Button;

        // Intro message
        switch (mode) {
            case CredentialsPane.Mode.INTRO:
                intro_message_label.set_markup(INTRO_MESSAGE);
            break;

            case CredentialsPane.Mode.FAILED_RETRY:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(_(
                    "Unrecognized User"), FAILED_RETRY_MESSAGE));
            break;

            case CredentialsPane.Mode.NOT_GALLERY_URL:
                intro_message_label.set_markup("<b>%s</b>\n\n%s".printf(
                    _(SERVICE_NAME + " Site Not Found"),
                    NOT_GALLERY_URL_MESSAGE));
            break;

            default:
                error("Invalid CredentialsPane mode");
        }

        // Gallery URL
        if (url != null) {
            url_entry.set_text(url);
            username_entry.grab_focus();
        }
        url_entry.changed.connect(on_url_or_username_changed);
        // User name
        if (username != null) {
            username_entry.set_text(username);
            password_entry.grab_focus();
        }
        username_entry.changed.connect(on_url_or_username_changed);

        // Key
        if (key != null) {
            key_entry.set_text(key);
            key_entry.grab_focus();
        }
        key_entry.changed.connect(on_url_or_username_changed);

        // Buttons
        go_back_button.clicked.connect(on_go_back_button_clicked);
        login_button.clicked.connect(on_login_button_clicked);
        login_button.set_sensitive((url != null) && (username != null));
    }

    private void on_login_button_clicked() {
        login(url_entry.get_text(), username_entry.get_text(),
            password_entry.get_text(), key_entry.get_text());
    }

    private void on_go_back_button_clicked() {
        go_back();
    }

    private void on_url_or_username_changed() {
        login_button.set_sensitive(
            ((url_entry.get_text() != "") &&
             (username_entry.get_text() != "")) ||
            (key_entry.get_text() != ""));
    }

    public void installed() {
        host.set_service_locked(false);

        // TODO: following line necessary?
        host.set_dialog_default_widget(login_button);
    }
}

internal class Session : Publishing.RESTSupport.Session {

    // Properties
    public string? url { get; private set; default = null; }
    public string? username { get; private set; default = null; }
    public string? key { get; private set; default = null; }

    public Session() {
    }

    public override bool is_authenticated() {
        return (null != key);
    }

    public void authenticate(string gallery_url, string username, string key) {
        this.url = gallery_url;
        this.username = username;
        this.key = key;

        notify_authenticated();
    }

    public void deauthenticate() {
        url = null;
        username = null;
        key = null;
    }

}

internal class Uploader : Publishing.RESTSupport.BatchUploader {

    private PublishingParameters parameters;

    public Uploader(Session session,
            Spit.Publishing.Publishable[] publishables,
            PublishingParameters parameters) {

        base(session, publishables);

        this.parameters = parameters;

    }

    protected override Publishing.RESTSupport.Transaction
            create_transaction(Spit.Publishing.Publishable publishable) {

        return new GalleryUploadTransaction((Session) get_session(),
            parameters, get_current_publishable());

    }

}

private string strip_session_url(string url) {

    // Remove the session URL from the beginning of this URL
    debug("Searching for \"%s\" in \"%s\"",
        REST_PATH, url);
    int item_loc =
        url.last_index_of(REST_PATH);

    if (-1 == item_loc)
        error("Did not find \"%s\" in the base of the new item " +
            "URL \"%s\"", REST_PATH, url);

    return url.substring(item_loc + REST_PATH.length);

}

}

// valac wants a default entry point, so valac gets a default entry point
private void dummy_main() {
}
// vi:ts=4:sw=4:et
