namespace ElementaryZero {

    public class Application : Gtk.Application {

        private MainWindow? window;

        const GLib.ActionEntry[] action_entries = {
            { "quit", on_quit_activate },
            { "about", on_about_activate }
        };

        protected override void activate () {
            if (window != null) {
                window.present ();
                return;
            }

            window = new MainWindow (this);
            window.present ();

            window.load ();
        }

        public static new Application get_default () {
            return (Application) GLib.Application.get_default ();
        }

        protected override void startup () {
            base.startup ();

            Granite.init ();

            set_accels_for_action ("app.quit", { "<Primary>q" });
        }

        public Application () {
            Object (application_id: "io.github.elementary-zero", flags: ApplicationFlags.DEFAULT_FLAGS);

            set_resource_base_path("/io/github/elementary-zero/");

            add_action_entries (action_entries, this);
        }

        void on_quit_activate () {
            quit ();
        }

        void on_about_activate () {
            var about = new Gtk.AboutDialog () {
                transient_for = window,
                modal = true,
                program_name = _("elementary-zero"),
                version = "1.0.0",
                comments = _("Package patcher for elementary OS"),
                copyright = "© 2026 fahmiirsyadk",
                license_type = Gtk.License.GPL_2_0,
                website = "https://github.com/fahmiirsyadk/elementary-zero",
                website_label = _("GitHub"),
                logo_icon_name = "application-x-executable"
            };
            about.present ();
        }
    }
}
