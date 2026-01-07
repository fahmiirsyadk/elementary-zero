namespace ElementaryZero {

    public class VersionService : Object {
        public signal void version_fetched (string? latest_version, string? current_version, bool is_outdated);

        public async void check_patch_status (string recipe_name) {
            try {
                string? latest_version = null;
                string? current_version = null;
                bool is_outdated = false;

                var state_mgr = StateManager.get_default ();
                current_version = state_mgr.get_installed_version (recipe_name);

                if (current_version == null) {
                    var now = new DateTime.now_utc ();
                    current_version = now.format ("%Y-%m-%dT%H:%M:%SZ");
                }

                var api_url = "https://api.github.com/repos/fahmiirsyadk/elementary-zero/commits?per_page=1";
                var session = new Soup.Session ();
                var message = new Soup.Message ("GET", api_url);
                message.get_request_headers ().append ("User-Agent", "elementary-zero/1.0");
                message.get_request_headers ().append ("Accept", "application/vnd.github.v3+json");

                InputStream? stream = null;
                try {
                    stream = yield session.send_async (message, Priority.DEFAULT, null);
                    var status = message.get_status ();

                    if (status == Soup.Status.OK) {
                        var parser = new Json.Parser ();
                        yield parser.load_from_stream_async (stream, null);

                        try {
                            stream.close (null);
                        } catch (Error e) {
                        }

                        var root_array = parser.get_root ().get_array ();
                        if (root_array != null && root_array.get_length () > 0) {
                            var latest_commit = root_array.get_object_element (0);

                            string? commit_sha = null;
                            if (latest_commit.has_member ("sha")) {
                                commit_sha = latest_commit.get_string_member ("sha");
                                if (commit_sha.length >= 7) {
                                    commit_sha = commit_sha.substring (0, 7);
                                }
                            }

                            if (latest_commit.has_member ("commit")) {
                                var commit_obj = latest_commit.get_object_member ("commit");
                                if (commit_obj.has_member ("committer")) {
                                    var committer = commit_obj.get_object_member ("committer");
                                    if (committer.has_member ("date")) {
                                        var commit_date_str = committer.get_string_member ("date");
                                        var commit_date = new DateTime.from_iso8601 (commit_date_str, null);

                                        if (commit_date != null) {
                                            var current_date = new DateTime.from_iso8601 (current_version, null);
                                            if (current_date == null) {
                                                if (current_version.length >= 10) {
                                                    var date_part = current_version.substring (0, 10);
                                                    current_date = new DateTime.from_iso8601 (date_part + "T00:00:00Z", null);
                                                }
                                            }

                                            if (current_date != null && commit_date.compare (current_date) > 0) {
                                                is_outdated = true;
                                            }

                                            latest_version = commit_date.format ("%Y-%m-%d");
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        warning ("GitHub API returned status: %u for elementary-zero commits", status);
                    }
                } catch (Error e) {
                    warning ("Error fetching elementary-zero latest commit: %s", e.message);
                } finally {
                    if (stream != null) {
                        try {
                            stream.close (null);
                        } catch (Error close_err) {
                        }
                    }
                }

                if (latest_version == null && current_version != null) {
                    is_outdated = false;
                } else if (latest_version == null) {
                    current_version = null;
                }

                version_fetched (latest_version, current_version, is_outdated);
            } catch (Error e) {
                warning ("Error checking patch status: %s", e.message);
                version_fetched (null, null, false);
            }
        }

        public async void check_version (string git_url, string? pinned_sha) {
            try {
                string? latest_version = null;
                string? current_version = null;
                bool is_outdated = false;

                if (pinned_sha != null && pinned_sha != "" && pinned_sha != "\"\"" && pinned_sha != "''") {
                    var clean_sha = pinned_sha.replace ("\"", "").replace ("'", "").strip ();
                    if (clean_sha.length >= 7) {
                        current_version = clean_sha.substring (0, 7);
                    } else if (clean_sha.length > 0) {
                        current_version = clean_sha;
                    }
                }

                MatchInfo match_info;
                var regex1 = new Regex ("github\\.com/([^/]+)/([^/]+)(?:\\.git)?$");
                var regex2 = new Regex ("github\\.com/([^/]+)/([^/]+)\\.git");
                string? owner = null;
                string? repo = null;

                if (regex1.match (git_url, 0, out match_info)) {
                    owner = match_info.fetch (1);
                    repo = match_info.fetch (2);
                } else if (regex2.match (git_url, 0, out match_info)) {
                    owner = match_info.fetch (1);
                    repo = match_info.fetch (2);
                }

                if (owner != null && repo != null) {
                    var session = new Soup.Session ();

                    var api_url = "https://api.github.com/repos/%s/%s/releases/latest".printf (owner, repo);
                    var message = new Soup.Message ("GET", api_url);
                    message.get_request_headers ().append ("User-Agent", "elementary-zero/1.0");
                    message.get_request_headers ().append ("Accept", "application/vnd.github.v3+json");

                    InputStream? stream = null;
                    try {
                        stream = yield session.send_async (message, Priority.DEFAULT, null);
                        var status = message.get_status ();

                        if (status == Soup.Status.OK) {
                            var parser = new Json.Parser ();
                            yield parser.load_from_stream_async (stream, null);

                            try {
                                stream.close (null);
                            } catch (Error e) {
                            }

                            var root = parser.get_root ().get_object ();
                            if (root.has_member ("tag_name")) {
                                latest_version = root.get_string_member ("tag_name");
                                if (latest_version.has_prefix ("v")) {
                                    latest_version = latest_version.substring (1);
                                }
                            }
                        } else if (status == Soup.Status.NOT_FOUND) {
                            if (stream != null) {
                                try {
                                    stream.close (null);
                                } catch (Error e) {
                                }
                            }

                            api_url = "https://api.github.com/repos/%s/%s/tags".printf (owner, repo);
                            message = new Soup.Message ("GET", api_url);
                            message.get_request_headers ().append ("User-Agent", "elementary-zero/1.0");
                            message.get_request_headers ().append ("Accept", "application/vnd.github.v3+json");

                            stream = yield session.send_async (message, Priority.DEFAULT, null);
                            var tags_status = message.get_status ();

                            if (tags_status == Soup.Status.OK) {
                                var parser = new Json.Parser ();
                                yield parser.load_from_stream_async (stream, null);

                                try {
                                    stream.close (null);
                                } catch (Error e) {
                                }

                                var root_array = parser.get_root ().get_array ();
                                if (root_array != null && root_array.get_length () > 0) {
                                    var first_tag = root_array.get_object_element (0);
                                    if (first_tag.has_member ("name")) {
                                        latest_version = first_tag.get_string_member ("name");
                                        if (latest_version.has_prefix ("v")) {
                                            latest_version = latest_version.substring (1);
                                        }
                                    }
                                }
                            } else {
                                if (tags_status != Soup.Status.NOT_FOUND) {
                                    warning ("GitHub tags API returned status: %u", tags_status);
                                }
                                if (stream != null) {
                                    try {
                                        stream.close (null);
                                    } catch (Error e) {
                                    }
                                }
                            }
                        } else {
                            if (status != Soup.Status.NOT_FOUND) {
                                warning ("GitHub releases API returned status: %u", status);
                            }
                            if (stream != null) {
                                try {
                                    stream.close (null);
                                } catch (Error e) {
                                }
                            }
                        }
                    } catch (Error e) {
                        warning ("Error fetching GitHub version: %s", e.message);
                    } finally {
                        if (stream != null) {
                            try {
                                stream.close (null);
                            } catch (Error close_err) {
                            }
                        }
                    }
                } else {
                    warning ("Could not parse GitHub URL: %s", git_url);
                }

                if (latest_version != null && current_version != null) {
                    is_outdated = (latest_version != current_version);
                }

                version_fetched (latest_version, current_version, is_outdated);
            } catch (Error e) {
                warning ("Error checking version: %s", e.message);
                version_fetched (null, null, false);
            }
        }
    }
}
