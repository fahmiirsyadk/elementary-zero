namespace ElementaryZero {

    public class PatchService : Object {
        public signal void patch_validated (string patch_path, bool is_valid, string? error);
        public signal void patch_applied (string patch_path, bool success, string? message);

        private Subprocess? current_process;

        public class PatchResult : Object {
            public bool success { get; set; default = false; }
            public string? error_message { get; set; }
            public Gee.ArrayList<string> conflicted_files { get; set; }
            public bool requires_rebase { get; set; default = false; }
            public string? suggested_sha { get; set; }

            public PatchResult () {
                conflicted_files = new Gee.ArrayList<string> ();
            }
        }

        public async PatchResult validate_patch (string patch_path, string source_dir) throws Error {
            var result = new PatchResult ();
            var patch_file = File.new_for_path (patch_path);

            if (!patch_file.query_exists ()) {
                result.error_message = "Patch file not found: " + patch_path;
                patch_validated (patch_path, false, result.error_message);
                return result;
            }

            try {
                var info = patch_file.query_info (FileAttribute.ACCESS_CAN_READ, FileQueryInfoFlags.NONE);
                if (!info.get_attribute_boolean (FileAttribute.ACCESS_CAN_READ)) {
                    result.error_message = "Patch file is not readable: " + patch_path;
                    patch_validated (patch_path, false, result.error_message);
                    return result;
                }
            } catch (Error e) {
                result.error_message = "Error checking patch file: " + e.message;
                patch_validated (patch_path, false, result.error_message);
                return result;
            }

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                    SubprocessFlags.STDERR_PIPE);
            launcher.set_cwd (source_dir);

            try {
                current_process = launcher.spawnv (new string[] {
                    "git", "apply", "--check", patch_path
                });

                yield current_process.wait_async ();

                if (current_process.get_exit_status () == 0) {
                    result.success = true;
                    patch_validated (patch_path, true, null);
                } else {
                    var stderr = current_process.get_stderr_pipe ();
                    if (stderr != null) {
                        var stderr_dis = new DataInputStream (stderr);
                        string? error_line;
                        var error_msg = new StringBuilder ();
                        while ((error_line = yield stderr_dis.read_line_async ()) != null) {
                            error_msg.append (error_line).append ("\n");

                            if (error_line.contains ("patch does not apply")) {
                                MatchInfo match_info;
                                var regex = new Regex (".*error: ([^:]+):.*");
                                if (regex.match (error_line, 0, out match_info)) {
                                    var file = match_info.fetch (1);
                                    if (file != null && file.length > 0) {
                                        result.conflicted_files.add (file);
                                    }
                                }
                            }
                        }
                        result.error_message = error_msg.str;
                    } else {
                        result.error_message = "Patch validation failed with exit code " +
                                             current_process.get_exit_status ().to_string ();
                    }
                    result.requires_rebase = true;
                    patch_validated (patch_path, false, result.error_message);
                }
            } catch (Error e) {
                result.error_message = "Error validating patch: " + e.message;
                patch_validated (patch_path, false, result.error_message);
            } finally {
                current_process = null;
            }

            return result;
        }

        public async PatchResult apply_patch (string patch_path, string source_dir) throws Error {
            var result = new PatchResult ();
            var patch_file = File.new_for_path (patch_path);

            if (!patch_file.query_exists ()) {
                result.error_message = "Patch file not found: " + patch_path;
                patch_applied (patch_path, false, result.error_message);
                return result;
            }

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE |
                                                    SubprocessFlags.STDERR_PIPE);
            launcher.set_cwd (source_dir);

            try {
                current_process = launcher.spawnv (new string[] {
                    "git", "apply", "--check", patch_path
                });

                yield current_process.wait_async ();
                var check_status = current_process.get_exit_status ();

                if (check_status == 0) {
                    current_process = launcher.spawnv (new string[] {
                        "git", "apply", patch_path
                    });
                } else {
                    result.requires_rebase = true;
                    current_process = launcher.spawnv (new string[] {
                        "git", "apply", "--3way", patch_path
                    });
                }

                var stdout = current_process.get_stdout_pipe ();
                var stderr = current_process.get_stderr_pipe ();
                var dis = new DataInputStream (stdout);
                var stderr_dis = stderr != null ? new DataInputStream (stderr) : null;

                string? line;
                var output_msg = new StringBuilder ();
                var error_msg = new StringBuilder ();

                while ((line = yield dis.read_line_async ()) != null) {
                    if (line.strip ().length > 0) {
                        output_msg.append (line).append ("\n");
                    }
                }

                if (stderr_dis != null) {
                    while ((line = yield stderr_dis.read_line_async ()) != null) {
                        error_msg.append (line).append ("\n");

                        if (line.contains ("CONFLICT") || line.contains ("conflict")) {
                            MatchInfo match_info;
                            var regex = new Regex (".*([^/]+/[^:]+):.*");
                            if (regex.match (line, 0, out match_info)) {
                                var file = match_info.fetch (1);
                                if (file != null && file.length > 0 && !result.conflicted_files.contains (file)) {
                                    result.conflicted_files.add (file);
                                }
                            }
                        }
                    }
                }

                yield current_process.wait_async ();

                if (current_process.get_exit_status () == 0) {
                    result.success = true;
                    if (output_msg.str.length > 0) {
                        result.error_message = output_msg.str;
                    }
                    patch_applied (patch_path, true, "Patch applied successfully");
                } else {
                    result.error_message = error_msg.str.length > 0 ? error_msg.str :
                                         "Patch application failed with exit code " +
                                         current_process.get_exit_status ().to_string ();
                    patch_applied (patch_path, false, result.error_message);
                }
            } catch (Error e) {
                result.error_message = "Error applying patch: " + e.message;
                patch_applied (patch_path, false, result.error_message);
            } finally {
                current_process = null;
            }

            return result;
        }

        public async bool check_compatibility (string patch_path, string git_sha) throws Error {

            return true;
        }

        public void cancel_patch_operation () {
            if (current_process != null) {
                try {
                    current_process.force_exit ();
                } catch (Error e) {
                    warning ("Error canceling patch operation: %s", e.message);
                }
            }
        }
    }
}
