namespace ElementaryZero {

    public class Recipe : Object {
        public string name { get; construct; }
        public string path { get; construct; }
        public string git_url { get; set; default = ""; }
        public string branch { get; set; default = "master"; }
        public string? pinned_sha { get; set; }
        public Gee.ArrayList<string> patches { get; construct; }

        public string? meson_options { get; set; }
        public string build_prefix { get; set; default = "/usr"; }
        public string[]? extra_build_flags { get; set; }

        public Gee.ArrayList<string> build_dependencies { get; construct; }
        public Gee.ArrayList<string> runtime_dependencies { get; construct; }

        public string? package_name { get; set; }

        public class PatchMetadata : Object {
            public string patch_path { get; set; }
            public string? compatible_version { get; set; }
            public string? last_tested_sha { get; set; }
            public bool requires_rebase { get; set; default = false; }
            public string? description { get; set; }
        }
        public Gee.ArrayList<PatchMetadata> patch_metadata { get; construct; }

        public RecipeStatus status { get; set; }
        public string? build_error { get; set; }
        public DateTime? last_built { get; set; }
        public bool is_installed { get; set; default = false; }

        public enum RecipeStatus {
            NOT_BUILT,
            BUILDING,
            BUILT,
            BUILD_FAILED,
            INSTALLING,
            INSTALLED,
            INSTALL_FAILED
        }

        public Recipe (string name, string path) {
            Object (
                name: name,
                path: path,
                patches: new Gee.ArrayList<string> (),
                build_dependencies: new Gee.ArrayList<string> (),
                runtime_dependencies: new Gee.ArrayList<string> (),
                patch_metadata: new Gee.ArrayList<PatchMetadata> (),
                status: RecipeStatus.NOT_BUILT
            );
        }

        public bool validate () {

            if (git_url == null || git_url == "") {
                build_error = "git_url is required";
                return false;
            }

            if (!git_url.has_prefix ("http://") && !git_url.has_prefix ("https://") &&
                !git_url.has_prefix ("git@") && !git_url.has_prefix ("git://")) {
                build_error = "Invalid git URL format";
                return false;
            }

            foreach (var patch_path in patches) {
                string absolute_patch_path;
                if (Path.is_absolute (patch_path)) {
                    absolute_patch_path = patch_path;
                } else {
                    absolute_patch_path = Path.build_filename (path, patch_path);
                }

                var patch_file = File.new_for_path (absolute_patch_path);
                if (!patch_file.query_exists ()) {
                    build_error = "Patch file not found: " + patch_path;
                    return false;
                }
            }

            return true;
        }

        public string get_status_icon () {
            switch (status) {
                case RecipeStatus.BUILT:
                case RecipeStatus.INSTALLED:
                    return "emblem-ok-symbolic";
                case RecipeStatus.BUILD_FAILED:
                case RecipeStatus.INSTALL_FAILED:
                    return "dialog-error-symbolic";
                case RecipeStatus.BUILDING:
                case RecipeStatus.INSTALLING:
                    return "process-working-symbolic";
                default:
                    return "package-x-generic-symbolic";
            }
        }

        public string get_status_text () {
            switch (status) {
                case RecipeStatus.NOT_BUILT:
                    return _("Not built");
                case RecipeStatus.BUILDING:
                    return _("Building...");
                case RecipeStatus.BUILT:
                    return _("Built");
                case RecipeStatus.BUILD_FAILED:
                    return _("Build failed");
                case RecipeStatus.INSTALLING:
                    return _("Installing...");
                case RecipeStatus.INSTALLED:
                    return _("Installed");
                case RecipeStatus.INSTALL_FAILED:
                    return _("Install failed");
                default:
                    return _("Unknown");
            }
        }
    }
}
