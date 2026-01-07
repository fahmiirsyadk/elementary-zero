namespace ElementaryZero.Panes {

    public class RecipePane : BasePane {
        public Recipe recipe { get; set; }
        private BuildService build_service;
        private InstallService install_service;
        private VersionService version_service;
        private Gee.HashMap<string, Gtk.Switch> patch_switches;

        private Granite.HeaderLabel version_label;
        private Gtk.Label version_text;
        private Gtk.Image version_icon;
        private Gtk.Box version_box;

        private Granite.HeaderLabel status_label;
        private Gtk.Box status_badge;
        private Gtk.Box status_box;

        private Gtk.Button install_btn;
        private Gtk.Button rollback_btn;

        public static RecipePane create (Recipe recipe) {
            if (recipe == null) {
                error ("Recipe cannot be null");
            }

            var recipe_name = recipe.name ?? "Unknown";
            var display_name = get_display_name (recipe_name);
            var recipe_description = _("Customize and patch %s").printf (display_name);

            var pane = new RecipePane.with_name (recipe_name, display_name, recipe_description);
            pane.recipe = recipe;
            return pane;
        }

        private static string get_display_name (string name) {

            var parts = name.split ("-");
            var words = new Gee.ArrayList<string> ();
            foreach (var part in parts) {
                if (part.length > 0) {
                    var word = part.substring (0, 1).up () + part.substring (1).down ();
                    words.add (word);
                }
            }
            return string.joinv (" ", words.to_array ());
        }

        private RecipePane.with_name (string name, string display_name, string description) {

            string icon_name = get_icon_for_recipe (name);
            GLib.Icon icon = new ThemedIcon (icon_name);

            Object (
                name: name,
                title: display_name,
                icon: icon,
                description: description,
                header: _("General")
            );
        }

        private static string get_icon_for_recipe (string recipe_name) {

            if (recipe_name.contains ("applications-menu") || recipe_name.contains ("slingshot")) {
                return "preferences-desktop";
            } else if (recipe_name.contains ("wingpanel")) {
                return "view-dual";
            } else if (recipe_name.contains ("file")) {
                return "folder";
            } else if (recipe_name.contains ("terminal")) {
                return "utilities-terminal";
            } else if (recipe_name.contains ("settings")) {
                return "preferences-desktop";
            } else {
                return "application-x-executable";
            }
        }

        construct {
            build_service = new BuildService ();
            install_service = new InstallService ();
            version_service = new VersionService ();
            patch_switches = new Gee.HashMap<string, Gtk.Switch> ();

            version_label = new Granite.HeaderLabel (_("Version")) {
                secondary_text = _("Current and latest available version"),
                hexpand = true
            };

            var version_container = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                halign = Gtk.Align.END,
                valign = Gtk.Align.CENTER
            };

            version_icon = new Gtk.Image.from_icon_name ("dialog-information-symbolic") {
                valign = Gtk.Align.CENTER
            };

            version_text = new Gtk.Label (_("Checking...")) {
                halign = Gtk.Align.END,
                valign = Gtk.Align.CENTER
            };

            version_container.append (version_icon);
            version_container.append (version_text);

            version_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            version_box.append (version_label);
            version_box.append (version_container);

            status_label = new Granite.HeaderLabel (_("Status")) {
                secondary_text = _("Current build and installation status"),
                hexpand = true
            };

            status_badge = create_status_badge (Recipe.RecipeStatus.NOT_BUILT, false);

            status_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            status_box.append (status_label);
            status_box.append (status_badge);

            var actions_label = new Granite.HeaderLabel (_("Actions")) {
                secondary_text = _("Build, install or rollback the package"),
                hexpand = true
            };

            install_btn = create_action_button (_("Build & Install"), "system-software-install-symbolic", true);
            install_btn.clicked.connect (() => {
                install_recipe.begin ();
            });

            rollback_btn = create_action_button (_("Rollback"), "edit-undo-symbolic", false);
            rollback_btn.add_css_class (Granite.CssClass.DESTRUCTIVE);
            rollback_btn.clicked.connect (() => {
                rollback_recipe.begin ();
            });

            var actions_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            actions_box.append (actions_label);
            var actions_buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            actions_buttons.append (install_btn);
            actions_buttons.append (rollback_btn);
            actions_box.append (actions_buttons);

            content_area.append (version_box);
            content_area.append (status_box);
            content_area.append (actions_box);

        }

        private void connect_signals () {
            if (recipe != null) {
                recipe.notify["status"].connect (update_ui);
            }

            version_service.version_fetched.connect ((latest, current, outdated) => {

                update_version_info (latest, current, outdated);
                update_patch_status (latest, current, outdated);
            });

            check_patch_status.begin ();

            install_service.install_complete.connect ((success, error) => {
                if (success) {
                    update_ui ();
                }
            });
        }

        private void update_version_info (string? latest_version, string? current_version, bool is_outdated) {

            if (latest_version != null && current_version != null) {
                version_text.set_text (_("%s (latest: %s)").printf (current_version, latest_version));
            } else if (current_version != null) {
                version_text.set_text (current_version);
            } else {
                version_text.set_text (_("Unknown"));
            }
        }

        private void update_patch_status (string? latest_version, string? current_version, bool is_outdated) {

            if (recipe != null) {
                update_status_badge ();
            }
        }

        private Gtk.Box create_status_badge (Recipe.RecipeStatus status, bool is_installed) {
            var badge_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                halign = Gtk.Align.END,
                valign = Gtk.Align.CENTER
            };

            Gtk.Widget? icon = null;
            string text = "";
            string css_class = "";

            switch (status) {
                case Recipe.RecipeStatus.NOT_BUILT:
                    icon = new Gtk.Image.from_icon_name ("content-loading-symbolic");
                    text = _("Not Built");
                    css_class = "dim-label";
                    break;
                case Recipe.RecipeStatus.BUILDING:
                    var spinner = new Gtk.Spinner () {
                        spinning = true,
                        visible = true
                    };
                    icon = spinner;
                    text = _("Building...");
                    css_class = "accent";
                    break;
                case Recipe.RecipeStatus.BUILT:
                    icon = new Gtk.Image.from_icon_name ("emblem-ok-symbolic");
                    text = _("Built");
                    css_class = "success";
                    break;
                case Recipe.RecipeStatus.INSTALLING:
                    var spinner = new Gtk.Spinner () {
                        spinning = true,
                        visible = true
                    };
                    icon = spinner;
                    text = _("Installing...");
                    css_class = "accent";
                    break;
                case Recipe.RecipeStatus.INSTALLED:
                    icon = new Gtk.Image.from_icon_name ("emblem-default-symbolic");
                    text = _("Installed");
                    css_class = "success";
                    break;
                case Recipe.RecipeStatus.BUILD_FAILED:
                case Recipe.RecipeStatus.INSTALL_FAILED:
                    icon = new Gtk.Image.from_icon_name ("dialog-error-symbolic");
                    text = _("Failed");
                    css_class = "error";
                    break;
            }

            if (icon != null) {
                badge_box.append (icon);
            }

            var label = new Gtk.Label (text) {
                halign = Gtk.Align.START
            };
            if (css_class != "") {
                label.add_css_class (css_class);
            }
            badge_box.append (label);

            return badge_box;
        }

        private void update_status_badge () {
            if (status_badge != null) {
                status_box.remove (status_badge);
            }
            status_badge = create_status_badge (recipe.status, recipe.is_installed);
            status_box.append (status_badge);
        }

        private Gtk.Button create_action_button (string label_text, string icon_name, bool is_suggested) {
            var button = new Gtk.Button () {
                halign = Gtk.Align.END,
                valign = Gtk.Align.CENTER
            };

            if (is_suggested) {
                button.add_css_class ("suggested-action");
            }

            var button_content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            button_content.append (new Gtk.Image.from_icon_name (icon_name));
            button_content.append (new Gtk.Label (label_text));
            button.child = button_content;

            return button;
        }

        private string get_patch_display_name (string patch_path) {
            var basename = Path.get_basename (patch_path);

            if (basename.has_suffix (".patch")) {
                basename = basename.substring (0, basename.length - 6);
            }

            var parts = basename.split ("-");
            var words = new Gee.ArrayList<string> ();
            foreach (var part in parts) {
                if (part.length > 0) {
                    var word = part.substring (0, 1).up () + part.substring (1).down ();
                    words.add (word);
                }
            }
            return string.joinv (" ", words.to_array ());
        }

        private string get_patch_description (string patch_path) {
            var basename = Path.get_basename (patch_path);

            try {
                var file = File.new_for_path (patch_path);
                if (file.query_exists ()) {
                    var dis = new DataInputStream (file.read ());
                    var first_line = dis.read_line ();
                    if (first_line != null && first_line.has_prefix ("Subject:")) {
                        return first_line.substring (7).strip ();
                    }
                }
            } catch (Error e) {

            }
            return _("Apply this patch to the package");
        }

        private void add_patch_row (string patch_path) {
            var patch_name = get_patch_display_name (patch_path);
            var patch_description = get_patch_description (patch_path);

            Recipe.PatchMetadata? patch_meta = null;
            foreach (var meta in recipe.patch_metadata) {
                if (meta.patch_path == patch_path) {
                    patch_meta = meta;
                    break;
                }
            }

            if (patch_meta != null && patch_meta.description != null && patch_meta.description != "") {
                patch_description = patch_meta.description;
            }

            var patch_label = new Granite.HeaderLabel (patch_name) {
                secondary_text = patch_description,
                hexpand = true
            };

            var patch_switch = new Gtk.Switch () {
                valign = Gtk.Align.CENTER,
                active = true
            };

            patch_switches[patch_path] = patch_switch;

            Gtk.Widget? compatibility_widget = null;
            if (patch_meta != null && patch_meta.requires_rebase) {
                var warning_icon = new Gtk.Image.from_icon_name ("dialog-warning-symbolic") {
                    tooltip_text = _("This patch may require rebasing"),
                    valign = Gtk.Align.CENTER,
                    pixel_size = 16
                };
                warning_icon.add_css_class ("warning");
                compatibility_widget = warning_icon;
            } else if (patch_meta != null && patch_meta.compatible_version != null) {
                var ok_icon = new Gtk.Image.from_icon_name ("emblem-ok-symbolic") {
                    tooltip_text = _("Compatible with version: %s").printf (patch_meta.compatible_version),
                    valign = Gtk.Align.CENTER,
                    pixel_size = 16
                };
                ok_icon.add_css_class ("success");
                compatibility_widget = ok_icon;
            }

            var patch_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            patch_box.append (patch_label);
            if (compatibility_widget != null) {
                patch_box.append (compatibility_widget);
            }
            patch_box.append (patch_switch);

            content_area.append (patch_box);
        }

        public override bool load () {
            if (recipe == null) {
                warning ("Recipe is null in RecipePane.load()");
                return false;
            }

            foreach (var patch_path in recipe.patches) {
                add_patch_row (patch_path);
            }

            if (recipe.patches.size == 0) {
                var no_patches_label = new Granite.HeaderLabel (_("No Patches")) {
                    secondary_text = _("No patches available for this recipe"),
                    hexpand = true
                };
                content_area.append (no_patches_label);
            }

            connect_signals ();

            check_version.begin ();

            update_ui ();
            is_load_success = true;
            return true;
        }

        private async void check_version () {
            yield version_service.check_version (recipe.git_url, recipe.pinned_sha);
        }

        private async void check_patch_status () {
            yield version_service.check_patch_status (recipe.name);
        }

        protected override void do_reset () {

            if (recipe.is_installed) {
                rollback_recipe.begin ();
            }
        }

        private void update_ui () {
            bool is_building = recipe.status == Recipe.RecipeStatus.BUILDING;
            bool is_installing = recipe.status == Recipe.RecipeStatus.INSTALLING;

            install_btn.set_sensitive (!is_building && !is_installing);

            update_button_content (install_btn,
                recipe.is_installed ? _("Reinstall") : _("Build & Install"),
                "system-software-install-symbolic");

            rollback_btn.set_sensitive (recipe.is_installed && !is_building && !is_installing);

            update_status_badge ();

            if (is_building || is_installing) {
                version_icon.set_from_icon_name ("process-working-symbolic");
            } else if (recipe.is_installed) {
                version_icon.set_from_icon_name ("emblem-default-symbolic");
            } else {
                version_icon.set_from_icon_name ("dialog-information-symbolic");
            }
        }

        private void update_button_content (Gtk.Button button, string label_text, string icon_name) {
            var button_content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            button_content.append (new Gtk.Image.from_icon_name (icon_name));
            button_content.append (new Gtk.Label (label_text));
            button.child = button_content;
        }

        private async void install_recipe () {
            install_btn.set_sensitive (false);

            var dialog = new Widgets.InstallDialog (get_root () as Gtk.Window,
                                                   _("Installing %s").printf (recipe.name ?? "package"));

            if (recipe.build_dependencies.size > 0) {
                dialog.show_dependencies_panel (recipe.build_dependencies);
            } else {

                dialog.show_build_content ();
            }

            dialog.present ();

            bool deps_ready = false;
            dialog.dependencies_installed.connect (() => {
                deps_ready = true;
                dialog.show_build_content ();
                proceed_with_build.begin (dialog);
            });

            if (recipe.build_dependencies.size == 0) {
                deps_ready = true;
                yield proceed_with_build (dialog);
            }

            dialog.cancelled.connect (() => {
                if (!deps_ready) {
                    install_btn.set_sensitive (true);
                    update_ui ();
                }
            });
        }

        private async void proceed_with_build (Widgets.InstallDialog dialog) {

            bool cancelled = false;
            ulong build_progress_id = 0;
            ulong build_progress_percent_id = 0;
            ulong build_complete_id = 0;
            ulong install_progress_id = 0;
            ulong install_complete_id = 0;

            var enabled_patches = new Gee.ArrayList<string> ();
            foreach (var patch_path in recipe.patches) {
                var switch_widget = patch_switches[patch_path];
                if (switch_widget != null && switch_widget.get_active ()) {
                    enabled_patches.add (patch_path);
                }
            }

            build_progress_id = build_service.build_progress.connect ((message) => {
                dialog.append_log (message);

                if (message.has_prefix ("Step ")) {
                    MatchInfo match_info;
                    if (/Step (\d+)\/5: (.+)/.match (message, 0, out match_info)) {
                        dialog.set_status (match_info.fetch (2));
                    }
                }
            });

            build_progress_percent_id = build_service.build_progress_percent.connect ((percent) => {
                dialog.set_progress (percent);
            });

            build_complete_id = build_service.build_complete.connect ((success, error) => {
                if (success) {
                    dialog.append_log ("");
                    dialog.append_log ("Build completed. Starting installation...");
                    dialog.set_status (_("Starting installation..."));
                    update_ui ();
                } else {
                    dialog.set_complete (false, error);
                    if (build_progress_id != 0) {
                        build_service.disconnect (build_progress_id);
                    }
                    if (build_progress_percent_id != 0) {
                        build_service.disconnect (build_progress_percent_id);
                    }
                    if (build_complete_id != 0) {
                        build_service.disconnect (build_complete_id);
                    }
                }
            });

            install_progress_id = install_service.install_progress.connect ((message) => {
                dialog.append_log (message);
                dialog.set_status (_("Installing..."));
            });

            install_complete_id = install_service.install_complete.connect ((success, error) => {
                dialog.set_complete (success, error);
                if (build_progress_id != 0) {
                    build_service.disconnect (build_progress_id);
                }
                if (build_progress_percent_id != 0) {
                    build_service.disconnect (build_progress_percent_id);
                }
                if (build_complete_id != 0) {
                    build_service.disconnect (build_complete_id);
                }
                if (install_progress_id != 0) {
                    install_service.disconnect (install_progress_id);
                }
                if (install_complete_id != 0) {
                    install_service.disconnect (install_complete_id);
                }

                if (success) {
                    var build_dir = Path.build_filename (recipe.path, "_work", "src", "build");
                    dialog.set_artifacts (build_dir);
                }
            });

            dialog.cancelled.connect (() => {
                cancelled = true;
                build_service.cancel_build ();
                install_service.cancel_install ();
            });

            yield build_service.build_recipe (recipe, enabled_patches);

            if (cancelled) {
                install_btn.set_sensitive (true);
                update_ui ();
                return;
            }

            if (recipe.status == Recipe.RecipeStatus.BUILT) {
                try {
                    yield install_service.install_recipe (recipe);
                } catch (Error e) {
                    dialog.set_complete (false, e.message);
                }
            } else {
                dialog.set_complete (false, "Build failed, cannot install");
            }

            if (!cancelled && !dialog.get_is_cancelled ()) {

            }

            install_btn.set_sensitive (true);
            update_ui ();
        }

        private async void rollback_recipe () {
            rollback_btn.set_sensitive (false);
            update_ui ();

            var dialog = new Widgets.InstallDialog (get_root () as Gtk.Window,
                                                   _("Rolling back %s").printf (recipe.name ?? "package"));
            dialog.present ();

            bool cancelled = false;
            ulong progress_id = 0;
            ulong complete_id = 0;

            dialog.cancelled.connect (() => {
                cancelled = true;
                install_service.cancel_install ();
            });

            progress_id = install_service.install_progress.connect ((message) => {
                dialog.append_log (message);
            });

            complete_id = install_service.install_complete.connect ((success, error) => {
                dialog.set_complete (success, error);
                if (progress_id != 0) {
                    install_service.disconnect (progress_id);
                }
                if (complete_id != 0) {
                    install_service.disconnect (complete_id);
                }
            });

            yield install_service.rollback_recipe (recipe);

            if (!cancelled && !dialog.get_is_cancelled ()) {

            }

            rollback_btn.set_sensitive (true);
            update_ui ();
        }

    }
}
