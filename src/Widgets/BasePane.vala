namespace ElementaryZero {

    public abstract class BasePane : Switchboard.SettingsPage {
        public signal void restored ();

        public abstract bool load ();
        protected abstract void do_reset ();

        protected bool is_load_success { get; protected set; }
        protected Gtk.Box content_area;

        protected BasePane () {
        }

        construct {
            show_end_title_buttons = true;

            is_load_success = false;
            set_margin_top (24);

            content_area = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
                vexpand = true,
                hexpand = true
            };
            content_area.set_margin_start (24);
            content_area.set_margin_end (24);
            content_area.set_margin_bottom (24);
            content_area.set_margin_top (0);
            child = content_area;

            var reset = add_button (_("Reset to Default"));

            reset.clicked.connect (on_click_reset);

            bind_property ("is_load_success", content_area, "sensitive", BindingFlags.DEFAULT | BindingFlags.SYNC_CREATE);
            bind_property ("is_load_success", reset, "sensitive", BindingFlags.DEFAULT | BindingFlags.SYNC_CREATE);
        }

        private void on_click_reset () {
            var reset_confirm_dialog = new Granite.MessageDialog.with_image_from_icon_name (
                _("Reset to Default?"),
                _("All settings in this pane will be restored to the factory defaults. This action can't be undone."),
                "dialog-warning", Gtk.ButtonsType.CANCEL
            ) {
                modal = true,
                transient_for = (Gtk.Window) get_root ()
            };
            var reset_button = reset_confirm_dialog.add_button (_("Reset"), Gtk.ResponseType.ACCEPT);
            reset_button.add_css_class (Granite.CssClass.DESTRUCTIVE);
            reset_confirm_dialog.response.connect ((response_id) => {
                if (response_id != Gtk.ResponseType.ACCEPT) {
                    reset_confirm_dialog.destroy ();
                    return;
                }

                do_reset ();
                reset_confirm_dialog.destroy ();
                restored ();
            });
            reset_confirm_dialog.present ();
        }
    }
}
