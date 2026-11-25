#include "my_application.h"

#include <glib.h>

// Make the bundled hicolor icon theme discoverable by GTK before it
// initializes, so gtk_window_set_icon_name("wishare") resolves.
static void add_bundled_data_dir() {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable == nullptr) return;
  g_autofree gchar* directory = g_path_get_dirname(executable);
  g_autofree gchar* data = g_build_filename(directory, "data", nullptr);
  const gchar* existing = g_getenv("XDG_DATA_DIRS");
  g_autofree gchar* updated = g_strdup_printf(
      "%s:%s", data,
      existing != nullptr ? existing : "/usr/local/share:/usr/share");
  g_setenv("XDG_DATA_DIRS", updated, TRUE);
}

int main(int argc, char** argv) {
  add_bundled_data_dir();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
