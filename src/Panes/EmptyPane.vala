namespace ElementaryZero.Panes {

    public class EmptyPane : BasePane {
        public signal void download_requested ();

        public EmptyPane () {
            Object (
                name: "empty",
                title: _("No Recipes"),
                icon: new ThemedIcon ("dialog-information"),
                description: _("No recipes found in the recipes directory"),
                header: _("Information")
            );
        }

        construct {
            var placeholder = new Granite.Placeholder (_("No Recipes Found")) {
                description = _("Download recipes from GitHub or add them manually to get started."),
                icon = new ThemedIcon ("folder-open")
            };

            var download_button = placeholder.append_button (
                new ThemedIcon ("view-refresh"),
                _("Download Recipes"),
                _("Get patches from elementary-zero repository")
            );

            download_button.clicked.connect (() => {
                download_requested ();
            });

            content_area.append (placeholder);
        }

        public override bool load () {
            is_load_success = true;
            return true;
        }

        protected override void do_reset () {
        }
    }
}
