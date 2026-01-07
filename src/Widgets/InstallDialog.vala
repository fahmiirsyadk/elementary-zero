namespace ElementaryZero.Widgets {

    public class InstallDialog : Gtk.Dialog {
        private Gtk.TextView log_view;
        private Gtk.TextBuffer log_buffer;
        private Gtk.Button close_btn;
        private Gtk.Button cancel_btn;
        private Gtk.Button continue_btn;
        private Gtk.Button reinstall_all_deps_btn;
        private Gtk.Spinner spinner;
        private Gtk.Label status_label;
        private Gtk.ProgressBar progress_bar;
        private Gtk.SearchEntry log_search;
        private Gtk.ComboBoxText log_filter;
        private Gtk.Box error_suggestions_box;
        private Gtk.Expander artifacts_expander;
        private Gtk.Box dependencies_panel;
        private Gtk.Box dependency_list_box;
        private Gtk.Button install_all_deps_btn;
        private Gtk.Box main_content_box;
        private Gtk.Box toolbar;
        private Gtk.ScrolledWindow scrolled;
        private Gtk.Box loading_box;
        private bool is_complete;
        private bool is_cancelled;
        private bool auto_scroll = true;
        private double current_progress = 0.0;
        private Gee.ArrayList<string> log_lines;
        private string current_filter = "all";
        private int last_displayed_line_count = 0;
        private uint update_timeout_id = 0;
        private Gee.ArrayList<string>? recipe_dependencies = null;
        private delegate void DependenciesInstalledCallback ();

        public signal void cancelled ();
        public signal void dependencies_installed ();

        public InstallDialog (Gtk.Window? parent, string title) {
            Object (
                title: title,
                modal: true,
                transient_for: parent,
                destroy_with_parent: true
            );
        }

        construct {
            log_lines = new Gee.ArrayList<string> ();
            set_default_size (800, 600);
            set_resizable (true);

            var header = new Gtk.HeaderBar () {
                show_title_buttons = true,
                title_widget = new Gtk.Label (title)
            };
            set_titlebar (header);

            var content_area = get_content_area ();
            content_area.set_margin_start (12);
            content_area.set_margin_end (12);
            content_area.set_margin_top (12);
            content_area.set_margin_bottom (12);
            content_area.set_spacing (12);

            main_content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content_area.append (main_content_box);

            dependencies_panel = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
                visible = false
            };

            var deps_label = new Granite.HeaderLabel (_("Build Dependencies")) {
                secondary_text = _("Required packages for building. Missing dependencies will be highlighted."),
                hexpand = true
            };

            dependency_list_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_start = 24,
                margin_top = 12,
                hexpand = true
            };

            install_all_deps_btn = new Gtk.Button.with_label (_("Install All Dependencies")) {
                halign = Gtk.Align.CENTER,
                margin_top = 12
            };
            install_all_deps_btn.add_css_class ("suggested-action");

            dependencies_panel.append (deps_label);
            dependencies_panel.append (dependency_list_box);
            dependencies_panel.append (install_all_deps_btn);

            main_content_box.append (dependencies_panel);

            progress_bar = new Gtk.ProgressBar () {
                show_text = true,
                fraction = 0.0,
                visible = false
            };
            main_content_box.append (progress_bar);

            toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                visible = false
            };

            log_search = new Gtk.SearchEntry () {
                placeholder_text = _("Search logs..."),
                hexpand = true
            };
            log_search.search_changed.connect (on_search_changed);

            log_filter = new Gtk.ComboBoxText ();
            log_filter.append ("all", _("All"));
            log_filter.append ("info", _("Info"));
            log_filter.append ("warning", _("Warnings"));
            log_filter.append ("errors", _("Errors"));
            log_filter.set_active_id ("all");
            log_filter.changed.connect (() => {
                current_filter = log_filter.get_active_id () ?? "all";
                update_log_display ();
            });

            toolbar.append (log_search);
            toolbar.append (log_filter);
            main_content_box.append (toolbar);

            scrolled = new Gtk.ScrolledWindow () {
                vexpand = true,
                hexpand = true,
                min_content_height = 300
            };

            log_buffer = new Gtk.TextBuffer (null);

            var error_tag = log_buffer.create_tag ("error", null);
            error_tag.foreground = "#cc0000";
            error_tag.weight = Pango.Weight.BOLD;

            var warning_tag = log_buffer.create_tag ("warning", null);
            warning_tag.foreground = "#f57900";

            log_view = new Gtk.TextView.with_buffer (log_buffer) {
                editable = false,
                monospace = true,
                wrap_mode = Gtk.WrapMode.WORD
            };
            log_view.add_css_class ("log-view");

            scrolled.set_child (log_view);
            scrolled.set_visible (false);
            main_content_box.append (scrolled);

            error_suggestions_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                visible = false,
                margin_top = 12
            };
            main_content_box.append (error_suggestions_box);

            artifacts_expander = new Gtk.Expander (_("Build Information")) {
                visible = false,
                margin_top = 12
            };
            main_content_box.append (artifacts_expander);

            loading_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                margin_top = 12
            };

            spinner = new Gtk.Spinner () {
                spinning = true,
                visible = true
            };

            status_label = new Gtk.Label (_("Processing...")) {
                halign = Gtk.Align.START,
                hexpand = true
            };

            loading_box.append (spinner);
            loading_box.append (status_label);
            loading_box.set_visible (false);
            main_content_box.append (loading_box);

            cancel_btn = new Gtk.Button.with_label (_("Cancel")) {
                visible = true
            };
            cancel_btn.clicked.connect (() => {
                is_cancelled = true;
                cancelled ();
                destroy ();
            });

            continue_btn = new Gtk.Button.with_label (_("Continue")) {
                visible = false
            };
            continue_btn.add_css_class ("suggested-action");
            continue_btn.clicked.connect (() => {
                dependencies_installed ();
            });

            reinstall_all_deps_btn = new Gtk.Button.with_label (_("Reinstall All Dependencies")) {
                visible = false
            };
            reinstall_all_deps_btn.clicked.connect (() => {
                reinstall_all_dependencies.begin ();
            });

            close_btn = new Gtk.Button.with_label (_("Close")) {
                visible = false
            };
            close_btn.add_css_class ("suggested-action");
            close_btn.clicked.connect (() => {
                destroy ();
            });

            var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            button_box.append (reinstall_all_deps_btn);
            button_box.append (continue_btn);

            add_action_widget (cancel_btn, Gtk.ResponseType.CANCEL);
            add_action_widget (button_box, Gtk.ResponseType.ACCEPT);
            add_action_widget (close_btn, Gtk.ResponseType.CLOSE);

            is_complete = false;
            is_cancelled = false;
        }

        public void append_log (string message) {
            if (is_cancelled) {
                return;
            }

            log_lines.add (message);

            if (message.contains ("ERROR") || message.contains ("error") || message.contains ("failed")) {
                check_error_and_suggest (message);
            }

            schedule_incremental_update ();
        }

        private void schedule_incremental_update () {
            if (update_timeout_id != 0) {
                Source.remove (update_timeout_id);
            }

            update_timeout_id = Timeout.add (50, () => {
                update_log_display ();
                update_timeout_id = 0;
                return false;
            });
        }

        private void update_log_display () {
            string search_text = log_search.text.down ();

            int start_index = last_displayed_line_count;
            bool has_filter = current_filter != "all" || search_text.length > 0;

            if (has_filter || start_index == 0) {
                log_buffer.set_text ("");
                last_displayed_line_count = 0;
                start_index = 0;
            }

            Gtk.TextIter iter;
            log_buffer.get_end_iter (out iter);

            for (int i = start_index; i < log_lines.size; i++) {
                var line = log_lines[i];
                bool include = false;
                switch (current_filter) {
                    case "all":
                        include = true;
                        break;
                    case "errors":
                        include = line.down ().contains ("error") ||
                                 line.down ().contains ("failed");
                        break;
                    case "warning":
                        include = line.down ().contains ("warning") ||
                                 line.down ().contains ("warn");
                        break;
                    case "info":
                        include = !line.down ().contains ("error") &&
                                 !line.down ().contains ("warning") &&
                                 !line.down ().contains ("failed");
                        break;
                }

                if (include && search_text.length > 0) {
                    include = line.down ().contains (search_text);
                }

                if (include) {
                    Gtk.TextIter line_start;
                    log_buffer.get_end_iter (out line_start);
                    var start_mark = log_buffer.create_mark (null, line_start, false);

                    log_buffer.insert_at_cursor (line + "\n", -1);

                    Gtk.TextIter line_end;
                    log_buffer.get_end_iter (out line_end);

                    log_buffer.get_iter_at_mark (out line_start, start_mark);

                    var line_lower = line.down ();
                    if (line_lower.contains ("error") || line_lower.contains ("failed")) {
                        log_buffer.apply_tag_by_name ("error", line_start, line_end);
                    } else if (line_lower.contains ("warning")) {
                        log_buffer.apply_tag_by_name ("warning", line_start, line_end);
                    }

                    log_buffer.delete_mark (start_mark);
                }
            }

            last_displayed_line_count = log_lines.size;

            if (auto_scroll && start_index < log_lines.size) {
                Gtk.TextIter end_iter;
                log_buffer.get_end_iter (out end_iter);
                var mark = log_buffer.create_mark (null, end_iter, false);
                log_view.scroll_to_mark (mark, 0.0, false, 0.0, 0.0);
                log_buffer.delete_mark (mark);
            }
        }

        private void on_search_changed () {
            last_displayed_line_count = 0;
            update_log_display ();
        }

        private void check_error_and_suggest (string error_line) {
            if (error_suggestions_box.get_first_child () != null) {
                return;
            }

            error_suggestions_box.visible = true;

            var suggestion_label = new Gtk.Label (null) {
                use_markup = true,
                wrap = true,
                xalign = 0.0f
            };

            string suggestion = "";
            if (error_line.contains ("git") && error_line.contains ("clone")) {
                suggestion = _("Git clone failed. Check your internet connection and repository URL.");
            } else if (error_line.contains ("patch") && error_line.contains ("apply")) {
                suggestion = _("Patch application failed. The patch may be incompatible with the current source code. Try updating the pinned_sha in recipe.yaml.");
            } else if (error_line.contains ("meson") || error_line.contains ("ninja")) {
                suggestion = _("Build failed. Check that all build dependencies are installed and the source code is valid.");
            } else if (error_line.contains ("pkexec") || error_line.contains ("permission")) {
                suggestion = _("Permission denied. Make sure you entered the correct password and have administrative privileges.");
            }

            if (suggestion.length > 0) {
                suggestion_label.set_markup ("<b>" + _("Suggestion:") + "</b> " + suggestion);
                error_suggestions_box.append (suggestion_label);
            }
        }

        public void set_progress (double percent) {
            current_progress = percent.clamp (0.0, 1.0);
            progress_bar.fraction = current_progress;
            progress_bar.text = "%d%%".printf ((int) (current_progress * 100));
        }

        public void set_complete (bool success, string? error_message = null) {
            is_complete = true;
            cancel_btn.visible = false;
            close_btn.visible = true;
            spinner.spinning = false;
            spinner.visible = false;

            if (success) {
                set_progress (1.0);
            }

            if (!success && error_message != null) {
                append_log ("");
                append_log ("ERROR: " + error_message);
                status_label.set_text (_("Failed"));
                status_label.add_css_class ("error");
                check_error_and_suggest (error_message);
            } else {
                status_label.set_text (success ? _("Completed") : _("Failed"));
                if (!success) {
                    status_label.add_css_class ("error");
                }
            }

            append_log ("");
            append_log (success ? _("Operation completed successfully.") : _("Operation failed."));
        }

        public void set_artifacts (string build_dir, string? installed_files = null) {
            artifacts_expander.visible = true;

            var info_label = new Gtk.Label (null) {
                use_markup = true,
                wrap = true,
                xalign = 0.0f,
                selectable = true
            };

            var info_text = "<b>" + _("Build Directory:") + "</b> " + build_dir + "\n";
            if (installed_files != null) {
                info_text += "<b>" + _("Installed Files:") + "</b> " + installed_files;
            }

            info_label.set_markup (info_text);
            artifacts_expander.child = info_label;
        }

        public void set_status (string status) {
            status_label.set_text (status);
        }

        public bool get_is_cancelled () {
            return is_cancelled;
        }

        public void show_dependencies_panel (Gee.ArrayList<string> dependencies) {
            recipe_dependencies = dependencies;

            var child = dependency_list_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                dependency_list_box.remove (child);
                child = next;
            }

            progress_bar.set_visible (false);
            toolbar.set_visible (false);
            scrolled.set_visible (false);
            loading_box.set_visible (false);
            dependencies_panel.set_visible (true);
            continue_btn.set_visible (false);
            reinstall_all_deps_btn.set_visible (false);
            cancel_btn.set_visible (true);

            if (!install_all_deps_btn.has_css_class ("connected")) {
                install_all_deps_btn.clicked.connect (() => {
                    install_all_dependencies.begin ();
                });
                install_all_deps_btn.add_css_class ("connected");
            }

            show_all_dependencies_with_loading ();

            check_and_display_dependencies.begin ();
        }

        private void show_all_dependencies_with_loading (string? loading_text = null) {
            if (recipe_dependencies == null || recipe_dependencies.size == 0) {
                var none_label = new Gtk.Label (_("No dependencies specified")) {
                    halign = Gtk.Align.START,
                    margin_start = 24
                };
                none_label.add_css_class ("dim-label");
                dependency_list_box.append (none_label);
                install_all_deps_btn.set_visible (false);
                continue_btn.set_visible (true);
                return;
            }

            string display_text = loading_text ?? _("Checking %s...");

            foreach (var dep in recipe_dependencies) {
                var dep_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                    margin_top = 6
                };
                dep_row.set_data<string> ("package-name", dep);

                var spinner = new Gtk.Spinner () {
                    spinning = true,
                    visible = true
                };
                spinner.set_size_request (16, 16);

                var label = new Gtk.Label (display_text.printf (dep)) {
                    halign = Gtk.Align.START,
                    hexpand = true
                };
                label.add_css_class ("dim-label");

                dep_row.append (spinner);
                dep_row.append (label);

                dependency_list_box.append (dep_row);
            }
        }

        private async void check_and_display_dependencies () {
            if (recipe_dependencies == null || recipe_dependencies.size == 0) {
                return;
            }

            int missing_count = 0;
            var child = dependency_list_box.get_first_child ();
            int index = 0;

            while (child != null && index < recipe_dependencies.size) {
                var dep_row = child as Gtk.Box;
                var dep = recipe_dependencies[index];

                if (dep_row != null) {
                    var row_child = dep_row.get_first_child ();
                    while (row_child != null) {
                        var next = row_child.get_next_sibling ();
                        dep_row.remove (row_child);
                        row_child = next;
                    }

                    bool installed = yield check_package_installed (dep);

                    if (!installed) {
                        missing_count++;
                    }

                    Gtk.Image status_icon;
                    var label = new Gtk.Label (dep) {
                        halign = Gtk.Align.START,
                        hexpand = true
                    };

                    if (installed) {
                        status_icon = new Gtk.Image.from_icon_name ("emblem-default-symbolic") {
                            pixel_size = 16,
                            tooltip_text = _("Installed")
                        };
                        status_icon.add_css_class ("success");
                        label.add_css_class ("success");
                    } else {
                        status_icon = new Gtk.Image.from_icon_name ("package-x-generic-symbolic") {
                            pixel_size = 16,
                            tooltip_text = _("Missing")
                        };
                        status_icon.add_css_class ("error");
                        label.add_css_class ("error");
                    }

                    dep_row.append (status_icon);
                    dep_row.append (label);
                }

                child = child.get_next_sibling ();
                index++;
            }

            if (missing_count > 0) {
                install_all_deps_btn.set_visible (true);
                continue_btn.set_visible (false);
            } else {
                install_all_deps_btn.set_visible (false);
                continue_btn.set_visible (true);
                reinstall_all_deps_btn.set_visible (true);
            }
        }

        private async bool check_package_installed (string package_name) {
            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE |
                                                       GLib.SubprocessFlags.STDERR_PIPE);

            try {
                var process = launcher.spawnv (new string[] { "dpkg", "-l", package_name });
                yield process.wait_async ();

                if (process.get_exit_status () == 0) {
                    var stdout = process.get_stdout_pipe ();
                    if (stdout != null) {
                        var dis = new DataInputStream (stdout);
                        string? line;
                        while ((line = yield dis.read_line_async ()) != null) {
                            if (line.has_prefix ("ii") && line.contains (package_name)) {
                                return true;
                            }
                        }
                    }
                }
            } catch (Error e) {
            }

            try {
                var process = launcher.spawnv (new string[] { "pkg-config", "--exists", package_name });
                yield process.wait_async ();
                if (process.get_exit_status () == 0) {
                    return true;
                }
            } catch (Error e) {
            }

            try {
                var process = launcher.spawnv (new string[] { "which", package_name });
                yield process.wait_async ();
                if (process.get_exit_status () == 0) {
                    return true;
                }
            } catch (Error e) {
            }

            return false;
        }

        private async void install_all_dependencies () {
            if (recipe_dependencies == null || recipe_dependencies.size == 0) {
                return;
            }

            install_all_deps_btn.set_sensitive (false);
            install_all_deps_btn.set_label (_("Installing dependencies..."));

            var child = dependency_list_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                dependency_list_box.remove (child);
                child = next;
            }

            show_all_dependencies_with_loading (_("Installing %s..."));

            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE |
                                                       GLib.SubprocessFlags.STDERR_PIPE);

            try {
                var packages = new Gee.ArrayList<string> ();
                packages.add ("pkexec");
                packages.add ("apt");
                packages.add ("install");
                packages.add ("-y");
                foreach (var dep in recipe_dependencies) {
                    packages.add (dep);
                }

                var process = launcher.spawnv (packages.to_array ());

                var stdout = process.get_stdout_pipe ();
                var stderr = process.get_stderr_pipe ();
                if (stdout != null) {
                    var dis = new DataInputStream (stdout);
                    string? line;
                    while ((line = yield dis.read_line_async ()) != null) {
                        append_log (line);
                    }
                }
                if (stderr != null) {
                    var dis = new DataInputStream (stderr);
                    string? line;
                    while ((line = yield dis.read_line_async ()) != null) {
                        append_log (line);
                    }
                }

                yield process.wait_async ();

                int exit_code;
                try {
                    exit_code = process.get_exit_status ();
                } catch (Error e) {
                    yield restore_dependency_status_after_cancel ();
                    install_all_deps_btn.set_label (_("Install All Dependencies"));
                    install_all_deps_btn.set_sensitive (true);
                    return;
                }

                if (exit_code == 130 || exit_code == 126) {
                    yield restore_dependency_status_after_cancel ();
                    install_all_deps_btn.set_label (_("Install All Dependencies"));
                    install_all_deps_btn.set_sensitive (true);
                    return;
                }

                bool success = exit_code == 0;

                if (success) {
                    append_log (_("All dependencies installed successfully."));
                    yield check_and_display_dependencies ();
                    install_all_deps_btn.set_visible (false);
                    continue_btn.set_visible (true);
                    reinstall_all_deps_btn.set_visible (true);
                } else {
                    append_log (_("ERROR: Failed to install some dependencies."));
                    yield check_and_display_dependencies ();
                }

                install_all_deps_btn.set_label (_("Install All Dependencies"));
                install_all_deps_btn.set_sensitive (true);
            } catch (Error e) {
                warning ("Failed to install dependencies: %s", e.message);
                append_log (_("ERROR: %s").printf (e.message));
                if (e.message.down ().contains ("cancelled") ||
                    e.message.down ().contains ("permission denied") ||
                    e.message.down ().contains ("authentication failed")) {
                    yield restore_dependency_status_after_cancel ();
                } else {
                    yield check_and_display_dependencies ();
                }
                install_all_deps_btn.set_label (_("Install All Dependencies"));
                install_all_deps_btn.set_sensitive (true);
            }
        }

        public void show_build_content () {
            dependencies_panel.set_visible (false);
            progress_bar.set_visible (true);
            toolbar.set_visible (true);
            scrolled.set_visible (true);
            loading_box.set_visible (true);
            continue_btn.set_visible (false);
            reinstall_all_deps_btn.set_visible (false);
            cancel_btn.set_visible (true);
        }

        private async void reinstall_all_dependencies () {
            if (recipe_dependencies == null || recipe_dependencies.size == 0) {
                return;
            }

            reinstall_all_deps_btn.set_sensitive (false);
            reinstall_all_deps_btn.set_label (_("Reinstalling..."));
            continue_btn.set_sensitive (false);

            var child = dependency_list_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                dependency_list_box.remove (child);
                child = next;
            }

            show_all_dependencies_with_loading (_("Reinstalling %s..."));

            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE |
                                                       GLib.SubprocessFlags.STDERR_PIPE);

            try {
                var packages = new Gee.ArrayList<string> ();
                packages.add ("pkexec");
                packages.add ("apt");
                packages.add ("install");
                packages.add ("--reinstall");
                packages.add ("-y");
                foreach (var dep in recipe_dependencies) {
                    packages.add (dep);
                }

                var process = launcher.spawnv (packages.to_array ());

                var stdout = process.get_stdout_pipe ();
                var stderr = process.get_stderr_pipe ();
                if (stdout != null) {
                    var dis = new DataInputStream (stdout);
                    string? line;
                    while ((line = yield dis.read_line_async ()) != null) {
                        append_log (line);
                    }
                }
                if (stderr != null) {
                    var dis = new DataInputStream (stderr);
                    string? line;
                    while ((line = yield dis.read_line_async ()) != null) {
                        append_log (line);
                    }
                }

                yield process.wait_async ();

                int exit_code;
                try {
                    exit_code = process.get_exit_status ();
                } catch (Error e) {
                    yield restore_dependency_status_after_cancel ();
                    reinstall_all_deps_btn.set_label (_("Reinstall All Dependencies"));
                    reinstall_all_deps_btn.set_sensitive (true);
                    continue_btn.set_sensitive (true);
                    return;
                }

                if (exit_code == 130 || exit_code == 126) {
                    yield restore_dependency_status_after_cancel ();
                    reinstall_all_deps_btn.set_label (_("Reinstall All Dependencies"));
                    reinstall_all_deps_btn.set_sensitive (true);
                    continue_btn.set_sensitive (true);
                    return;
                }

                bool success = exit_code == 0;

                if (success) {
                    append_log (_("All dependencies reinstalled successfully."));
                    yield check_and_display_dependencies ();
                } else {
                    append_log (_("ERROR: Failed to reinstall some dependencies."));
                    yield check_and_display_dependencies ();
                }

                reinstall_all_deps_btn.set_label (_("Reinstall All Dependencies"));
                reinstall_all_deps_btn.set_sensitive (true);
                continue_btn.set_sensitive (true);
            } catch (Error e) {
                warning ("Failed to reinstall dependencies: %s", e.message);
                append_log (_("ERROR: %s").printf (e.message));
                if (e.message.down ().contains ("cancelled") ||
                    e.message.down ().contains ("permission denied") ||
                    e.message.down ().contains ("authentication failed")) {
                    yield restore_dependency_status_after_cancel ();
                } else {
                    yield check_and_display_dependencies ();
                }
                reinstall_all_deps_btn.set_label (_("Reinstall All Dependencies"));
                reinstall_all_deps_btn.set_sensitive (true);
                continue_btn.set_sensitive (true);
            }
        }

        private async void restore_dependency_status_after_cancel () {
            var child = dependency_list_box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                dependency_list_box.remove (child);
                child = next;
            }

            yield check_and_display_dependencies ();
        }

        private async void read_process_output (GLib.InputStream? stream) {
            if (stream == null) {
                return;
            }

            try {
                var dis = new DataInputStream (stream);
                string? line;
                while ((line = yield dis.read_line_async ()) != null) {
                    append_log (line);
                }
            } catch (Error e) {
            }
        }
    }
}
