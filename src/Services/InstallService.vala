namespace ElementaryZero {

    public class InstallService : Object {
        public signal void install_progress (string message);
        public signal void install_complete (bool success, string? error);

        private Subprocess? current_process;
        private Recipe? current_recipe;

        public async void install_recipe (Recipe recipe) throws Error {
            if (recipe.status != Recipe.RecipeStatus.BUILT) {
                throw new Error (Quark.from_string ("install"), 1, "Recipe must be built before installing");
            }

            recipe.status = Recipe.RecipeStatus.INSTALLING;
            current_recipe = recipe;

            try {
                var build_dir = Path.build_filename (recipe.path, "_work", "src", "build");
                var build_dir_file = File.new_for_path (build_dir);

                if (!build_dir_file.query_exists ()) {
                    throw new Error (Quark.from_string ("install"), 1,
                                   "Build directory not found: " + build_dir + "\n" +
                                   "Please build the recipe before installing.");
                }

                install_progress ("Starting installation for " + recipe.name + "...");
                install_progress ("Build directory: " + build_dir);
                install_progress ("This operation requires administrator privileges.");

                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                       SubprocessFlags.STDERR_MERGE);

                string[] argv = { "pkexec", "ninja", "-C", build_dir, "install" };
                current_process = launcher.spawnv (argv);

                var stdout = current_process.get_stdout_pipe ();
                var dis = new DataInputStream (stdout);
                string? line;

                while ((line = yield dis.read_line_async ()) != null) {
                    install_progress (line.strip ());
                }

                yield current_process.wait_async ();

                if (current_process.get_exit_status () == 0) {
                    install_progress ("Verifying installation...");
                    var verify_result = yield verify_installation (recipe);

                    if (!verify_result) {
                        install_progress ("WARNING: Installation verification incomplete");
                    }

                    yield restart_wingpanel ();

                    recipe.status = Recipe.RecipeStatus.INSTALLED;
                    recipe.is_installed = true;

                    var state_mgr = StateManager.get_default ();
                    state_mgr.set_recipe_installed (recipe.name, true);
                    var now = new DateTime.now_utc ();
                    state_mgr.set_installed_version (recipe.name, now.format ("%Y-%m-%dT%H:%M:%SZ"));

                    install_complete (true, null);
                } else {
                    recipe.status = Recipe.RecipeStatus.INSTALL_FAILED;
                    install_complete (false, "Install failed with exit code " +
                                   current_process.get_exit_status ().to_string ());
                }

            } catch (Error e) {
                recipe.status = Recipe.RecipeStatus.INSTALL_FAILED;
                install_complete (false, e.message);
            } finally {
                current_process = null;
                current_recipe = null;
            }
        }

        public async void rollback_recipe (Recipe recipe) {
            try {
                string? package_name = recipe.package_name;

                if (package_name == null || package_name == "") {
                    throw new Error (Quark.from_string ("rollback"), 1,
                                   "Package name not specified in recipe.\n" +
                                   "Please set 'package_name' in recipe.yaml for rollback to work.");
                }

                install_progress ("Rolling back " + recipe.name + "...");
                install_progress ("Reinstalling system package: " + package_name);
                install_progress ("This operation requires administrator privileges.");

                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                       SubprocessFlags.STDERR_MERGE);

                install_progress ("Updating package list...");
                string[] update_argv = { "pkexec", "apt", "update" };
                current_process = launcher.spawnv (update_argv);

                var stdout = current_process.get_stdout_pipe ();
                var dis = new DataInputStream (stdout);
                string? line;

                while ((line = yield dis.read_line_async ()) != null) {
                    if (line.strip ().length > 0) {
                        install_progress (line.strip ());
                    }
                }

                yield current_process.wait_async ();

                if (current_process.get_exit_status () != 0) {
                    throw new Error (Quark.from_string ("rollback"), 1,
                                   "Package list update failed with exit code " +
                                   current_process.get_exit_status ().to_string ());
                }

                install_progress ("Reinstalling " + package_name + "...");
                string[] reinstall_argv = { "pkexec", "apt", "install", "--reinstall", "-y", package_name };
                current_process = launcher.spawnv (reinstall_argv);

                stdout = current_process.get_stdout_pipe ();
                dis = new DataInputStream (stdout);

                while ((line = yield dis.read_line_async ()) != null) {
                    if (line.strip ().length > 0) {
                        install_progress (line.strip ());
                    }
                }

                yield current_process.wait_async ();

                if (current_process.get_exit_status () == 0) {
                    yield restart_wingpanel ();

                    recipe.status = Recipe.RecipeStatus.NOT_BUILT;
                    recipe.is_installed = false;

                    var state_mgr = StateManager.get_default ();
                    state_mgr.set_recipe_installed (recipe.name, false);

                    install_progress ("Rollback complete. Restored system package: " + package_name);
                    install_complete (true, null);
                } else {
                    install_complete (false, "Package reinstall failed with exit code " +
                                   current_process.get_exit_status ().to_string () + "\n" +
                                   "The package '" + package_name + "' may not be available in repositories.");
                }

            } catch (Error e) {
                install_complete (false, e.message);
            } finally {
                current_process = null;
            }
        }

        private async bool verify_installation (Recipe recipe) {
            var build_dir = Path.build_filename (recipe.path, "_work", "src", "build");
            var build_dir_file = File.new_for_path (build_dir);

            if (!build_dir_file.query_exists ()) {
                return false;
            }

            return true;
        }

        private async void restart_wingpanel () {
            install_progress ("Restarting wingpanel...");

            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                       SubprocessFlags.STDERR_PIPE);

                string[] kill_argv = { "killall", "io.elementary.wingpanel" };
                try {
                    current_process = launcher.spawnv (kill_argv);
                    yield current_process.wait_async ();
                    GLib.Timeout.add (1000, () => {
                        install_progress ("Wingpanel restarted.");
                        return false;
                    });
                } catch (Error e) {
                    install_progress ("Wingpanel restart (process may not have been running)");
                } finally {
                    current_process = null;
                }
            } catch (Error e) {
                warning ("Error restarting wingpanel: %s", e.message);
                install_progress ("WARNING: Could not restart wingpanel automatically");
            }
        }

        public void cancel_install () {
            if (current_process != null) {
                try {
                    current_process.force_exit ();
                } catch (Error e) {
                    warning ("Error canceling install: %s", e.message);
                }
            }
        }
    }
}
