namespace ElementaryZero {

    public class RecipeDownloader : Object {
        public signal void download_progress (string message);
        public signal void download_complete (bool success, string? error);

        private const string RECIPES_REPO_URL = "https://github.com/fahmiirsyadk/elementary-zero.git";
        private const string RECIPES_API_URL = "https://api.github.com/repos/fahmiirsyadk/elementary-zero/contents/recipes";
        private Subprocess? current_process;
        private string recipes_dir;

        public RecipeDownloader () {
            recipes_dir = Path.build_filename (Environment.get_user_data_dir (), "elementary-zero", "recipes");
        }

        public string get_recipes_dir () {
            return recipes_dir;
        }

        public async bool sync_recipes () {
            try {
                var recipes_parent = Path.get_dirname (recipes_dir);
                var repo_dir = Path.build_filename (recipes_parent, ".repo");
                var repo_file = File.new_for_path (repo_dir);

                download_progress ("Checking for recipe updates...");

                if (repo_file.query_exists ()) {
                    var success = yield update_repo (repo_dir);
                    if (!success) {
                        download_complete (false, "Failed to update recipes repository");
                        return false;
                    }
                } else {
                    var parent_file = File.new_for_path (recipes_parent);
                    if (!parent_file.query_exists ()) {
                        parent_file.make_directory_with_parents (null);
                    }

                    var success = yield clone_repo (repo_dir);
                    if (!success) {
                        download_complete (false, "Failed to clone recipes repository");
                        return false;
                    }
                }

                yield copy_recipes (repo_dir);

                download_progress ("Recipes synchronized successfully");
                download_complete (true, null);
                return true;

            } catch (Error e) {
                download_complete (false, e.message);
                return false;
            }
        }

        private async bool clone_repo (string repo_dir) throws Error {
            download_progress ("Downloading recipes from GitHub...");

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);

            current_process = launcher.spawnv (new string[] {
                "git", "clone", "--depth", "1", "--filter=blob:none", "--sparse",
                RECIPES_REPO_URL, repo_dir
            });

            var stdout = current_process.get_stdout_pipe ();
            var dis = new DataInputStream (stdout);
            string? line;

            while ((line = yield dis.read_line_async ()) != null) {
                download_progress (line);
            }

            yield current_process.wait_async ();

            if (current_process.get_exit_status () != 0) {
                return false;
            }

            launcher.set_cwd (repo_dir);
            current_process = launcher.spawnv (new string[] {
                "git", "sparse-checkout", "set", "recipes"
            });

            yield current_process.wait_async ();

            return current_process.get_exit_status () == 0;
        }

        private async bool update_repo (string repo_dir) throws Error {
            download_progress ("Checking for updates...");

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
            launcher.set_cwd (repo_dir);

            current_process = launcher.spawnv (new string[] {
                "git", "fetch", "--depth", "1", "origin", "main"
            });

            yield current_process.wait_async ();

            if (current_process.get_exit_status () != 0) {
                return false;
            }

            current_process = launcher.spawnv (new string[] {
                "git", "reset", "--hard", "origin/main"
            });

            var stdout = current_process.get_stdout_pipe ();
            var dis = new DataInputStream (stdout);
            string? line;

            while ((line = yield dis.read_line_async ()) != null) {
                download_progress (line);
            }

            yield current_process.wait_async ();

            return current_process.get_exit_status () == 0;
        }

        private async void copy_recipes (string repo_dir) throws Error {
            var source_recipes = Path.build_filename (repo_dir, "recipes");
            var source_file = File.new_for_path (source_recipes);

            if (!source_file.query_exists ()) {
                download_progress ("No recipes found in repository");
                return;
            }

            var dest_file = File.new_for_path (recipes_dir);
            if (!dest_file.query_exists ()) {
                dest_file.make_directory_with_parents (null);
            }

            download_progress ("Copying recipes...");

            var enumerator = source_file.enumerate_children (
                FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NONE
            );

            FileInfo? info;
            while ((info = enumerator.next_file ()) != null) {
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var recipe_name = info.get_name ();
                    var source_recipe = Path.build_filename (source_recipes, recipe_name);
                    var dest_recipe = Path.build_filename (recipes_dir, recipe_name);

                    yield copy_directory (source_recipe, dest_recipe);
                    download_progress ("Synced recipe: " + recipe_name);
                }
            }
        }

        private async void copy_directory (string source, string dest) throws Error {
            var source_file = File.new_for_path (source);
            var dest_file = File.new_for_path (dest);

            if (!dest_file.query_exists ()) {
                dest_file.make_directory_with_parents (null);
            }

            var enumerator = source_file.enumerate_children (
                FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NONE
            );

            FileInfo? info;
            while ((info = enumerator.next_file ()) != null) {
                var name = info.get_name ();
                var source_child = Path.build_filename (source, name);
                var dest_child = Path.build_filename (dest, name);

                if (info.get_file_type () == FileType.DIRECTORY) {
                    yield copy_directory (source_child, dest_child);
                } else {
                    var src = File.new_for_path (source_child);
                    var dst = File.new_for_path (dest_child);
                    src.copy (dst, FileCopyFlags.OVERWRITE, null, null);
                }
            }
        }

        public async Gee.ArrayList<string> list_available_recipes () {
            var recipes = new Gee.ArrayList<string> ();

            try {
                var session = new Soup.Session ();
                var message = new Soup.Message ("GET", RECIPES_API_URL);
                message.get_request_headers ().append ("User-Agent", "elementary-zero/1.0");
                message.get_request_headers ().append ("Accept", "application/vnd.github.v3+json");

                var stream = yield session.send_async (message, Priority.DEFAULT, null);
                var status = message.get_status ();

                if (status == Soup.Status.OK) {
                    var parser = new Json.Parser ();
                    yield parser.load_from_stream_async (stream, null);

                    var root_array = parser.get_root ().get_array ();
                    if (root_array != null) {
                        for (uint i = 0; i < root_array.get_length (); i++) {
                            var item = root_array.get_object_element (i);
                            if (item.has_member ("type") && item.get_string_member ("type") == "dir") {
                                if (item.has_member ("name")) {
                                    recipes.add (item.get_string_member ("name"));
                                }
                            }
                        }
                    }
                }

                try {
                    stream.close (null);
                } catch (Error e) {
                }
            } catch (Error e) {
                warning ("Error listing available recipes: %s", e.message);
            }

            return recipes;
        }

        public void cancel () {
            if (current_process != null) {
                try {
                    current_process.force_exit ();
                } catch (Error e) {
                    warning ("Error canceling download: %s", e.message);
                }
            }
        }
    }
}

