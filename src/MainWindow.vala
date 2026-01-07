namespace ElementaryZero {

    public class MainWindow : Gtk.ApplicationWindow {
        private Gtk.HeaderBar headerbar;
        private Categories categories;

        public MainWindow (Gtk.Application app) {
            Object (
                application: app
            );
        }

        construct {
            title = _("elementary-zero");

            headerbar = new Gtk.HeaderBar () {
                show_title_buttons = true,
                title_widget = new Gtk.Label (_("elementary-zero"))
            };

            set_titlebar (headerbar);

            set_default_size (900, 700);
            set_size_request (800, 600);
        }

        public void load () {
            categories = new Categories ();
            child = categories;

            headerbar.visible = false;

            categories.load ();
        }
    }
}
