namespace ElementaryZero {

    public class Categories : Gtk.Box {
        private List<BasePane> panes;
        private Gtk.Stack stack;
        private Granite.Toast toast;
        private RecipeManager recipe_manager;
        private RecipeDownloader recipe_downloader;

        ~Categories () {
            for (unowned List<BasePane> pane = panes; pane != null; pane = panes.first ()) {
                stack.remove (pane.data);
                panes.delete_link (pane);
            }
        }

        construct {
            recipe_manager = new RecipeManager ();
            recipe_downloader = new RecipeDownloader ();
            panes = new List<BasePane> ();
            stack = new Gtk.Stack ();

            var side_bar = new Switchboard.SettingsSidebar (stack) {
                show_title_buttons = true
            };
            side_bar.set_size_request (200, -1);
            side_bar.add_css_class ("small-sidebar");

            toast = new Granite.Toast (_("Operation completed successfully"));

            var overlay = new Gtk.Overlay () {
                child = stack
            };
            overlay.add_overlay (toast);

            var action_bar = new Gtk.ActionBar ();

            var sync_button = new Gtk.Button.with_label (_("Sync")) {
                tooltip_text = _("Download recipes from GitHub")
            };
            sync_button.set_icon_name ("view-refresh-symbolic");
            sync_button.clicked.connect (() => {
                sync_recipes ();
            });

            var menu = new GLib.Menu ();
            menu.append (_("About"), "app.about");

            var menu_button = new Gtk.MenuButton () {
                icon_name = "open-menu-symbolic",
                menu_model = menu,
                tooltip_text = _("Menu"),
                direction = Gtk.ArrowType.UP
            };

            action_bar.pack_start (sync_button);
            action_bar.pack_end (menu_button);

            var sidebar_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                vexpand = true
            };
            sidebar_box.append (side_bar);
            sidebar_box.append (action_bar);

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                hexpand = true,
                resize_start_child = false,
                shrink_start_child = false,
                shrink_end_child = false,
                start_child = sidebar_box,
                end_child = overlay
            };
            paned.set_position (250);

            append (paned);
        }

        public void load () {
            var recipes = recipe_manager.discover_recipes ();

            if (recipes.size == 0) {
                var empty_pane = new Panes.EmptyPane ();
                empty_pane.download_requested.connect (() => {
                    download_recipes.begin ();
                });
                stack.add_titled (empty_pane, "empty", _("No Recipes"));
                return;
            }

            foreach (var recipe in recipes) {
                var recipe_ref = recipe;
                if (recipe_ref == null) {
                    warning ("Skipping null recipe");
                    continue;
                }

                var pane = Panes.RecipePane.create (recipe_ref);
                panes.append (pane);

                pane.restored.connect (() => {
                    toast.send_notification ();
                });

                stack.add_titled (pane, pane.name, pane.title);
            }
            panes.foreach ((pane) => {
                bool ret = pane.load ();
                if (!ret) {
                    warning ("Failed to load pane: %s", pane.title);
                }
            });
        }

        private async void download_recipes () {
            var dialog = new Widgets.InstallDialog (
                (Gtk.Window) get_root (),
                _("Downloading Recipes")
            );

            recipe_downloader.download_progress.connect ((message) => {
                dialog.append_log (message);
            });

            recipe_downloader.download_complete.connect ((success, error) => {
                dialog.set_complete (success, error);
                if (success) {
                    toast.title = _("Recipes downloaded successfully");
                    toast.send_notification ();
                    Idle.add (() => {
                        reload_recipes ();
                        return false;
                    });
                }
            });

            dialog.cancelled.connect (() => {
                recipe_downloader.cancel ();
            });

            dialog.show_build_content ();
            dialog.present ();

            yield recipe_downloader.sync_recipes ();
        }

        public void sync_recipes () {
            download_recipes.begin ();
        }

        private void reload_recipes () {
            foreach (unowned var pane in panes) {
                stack.remove (pane);
            }
            panes = new List<BasePane> ();

            var visible_child = stack.get_visible_child ();
            if (visible_child != null && visible_child.name == "empty") {
                stack.remove (visible_child);
            }

            load ();
        }
    }
}
