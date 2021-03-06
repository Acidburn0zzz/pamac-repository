/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a get of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Pamac {

	class Manager : Gtk.Application {
		ManagerWindow manager_window;
		Database database;
		SearchProvider search_provider;
		uint search_provider_id;
		bool version;
		bool updates;
		string? pkgname;
		string? app_id;
		string? search;
		OptionEntry[] options;


		public Manager (Database database) {
			Object (application_id: "org.manjaro.pamac.manager", flags: ApplicationFlags.HANDLES_OPEN);
			this.database = database;
			database.enable_appstream ();

			version = false;
			updates = false;
			pkgname = null;
			app_id = null;
			search = null;
			options = new OptionEntry[5];
			options[0] = { "version", 0, 0, OptionArg.NONE, ref version, "Display version number", null };
			options[1] = { "updates", 0, 0, OptionArg.NONE, ref updates, "Display updates", null };
			options[2] = { "details", 0, 0, OptionArg.STRING, ref pkgname, "Display package details", "PACKAGE_NAME" };
			options[3] = { "details-id", 0, 0, OptionArg.STRING, ref app_id, "Display package details", "APP_ID" };
			options[4] = { "search", 0, 0, OptionArg.STRING, ref search, "Search packages", "SEARCH" };
			add_main_option_entries (options);

			search_provider_id = 0;
			search_provider = new SearchProvider (database);
			search_provider.show_details.connect ((app_id, timestamp) => {
				this.activate_action ("details-id", new Variant ("s", app_id));
			});
			search_provider.search_full.connect ((terms, timestamp) => {
				var str_builder = new StringBuilder ();
				foreach (unowned string str in terms) {
					if (str_builder.len > 0) {
						str_builder.append (" ");
					}
					str_builder.append (str);
				}
				if (manager_window == null) {
					create_manager_window ();
				}
				manager_window.display_package_queue.clear ();
				manager_window.search_button.active = true;
				var entry = manager_window.search_comboboxtext.get_child () as Gtk.Entry;
				entry.set_text (str_builder.str);
				manager_window.present_with_time (timestamp);
			});
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");
			base.startup ();

			// updates
			var action = new SimpleAction ("updates", null);
			action.activate.connect (() => {
				if (manager_window == null) {
					create_manager_window ();
				}
				manager_window.display_package_queue.clear ();
				manager_window.main_stack.visible_child_name = "browse";
				manager_window.browse_stack.visible_child_name = "updates";
				manager_window.present ();
			});
			this.add_action (action);
			// details
			action = new SimpleAction ("details", new VariantType ("s"));
			action.activate.connect  ((parameter) => {
				if (manager_window == null) {
					create_manager_window ();
					manager_window.refresh_packages_list ();
				}
				pkgname = parameter.get_string ();
				AlpmPackage? pkg = this.database.get_pkg (pkgname);
				if (pkg != null) {
					manager_window.display_package_details (pkg);
					manager_window.main_stack.visible_child_name = "details";
				}
				manager_window.present ();
			});
			this.add_action (action);
			// details_id
			action = new SimpleAction ("details-id", new VariantType ("s"));
			action.activate.connect  ((parameter) => {
				if (manager_window == null) {
					create_manager_window ();
					manager_window.refresh_packages_list ();
				}
				app_id = parameter.get_string ();
				Package? pkg = this.database.get_app_by_id (app_id);
				if (pkg != null) {
					manager_window.display_details (pkg);
					manager_window.main_stack.visible_child_name = "details";
				}
				manager_window.present ();
			});
			this.add_action (action);
		}

		void create_manager_window () {
			manager_window = new ManagerWindow (this, database);
			// quit accel
			var action =  new SimpleAction ("quit", null);
			action.activate.connect  (() => {this.quit ();});
			this.add_action (action);
			string[] accels = {"<Ctrl>Q", "<Ctrl>W"};
			this.set_accels_for_action ("app.quit", accels);
			// back accel
			action =  new SimpleAction ("back", null);
			action.activate.connect  (() => {manager_window.on_button_back_clicked ();});
			this.add_action (action);
			accels = {"<Alt>Left"};
			this.set_accels_for_action ("app.back", accels);
			// search accel
			action =  new SimpleAction ("search_accel", null);
			action.activate.connect  (() => {manager_window.search_button.activate ();});
			this.add_action (action);
			accels = {"<Ctrl>F"};
			this.set_accels_for_action ("app.search_accel", accels);
		}

		public override bool dbus_register (DBusConnection connection, string object_path) {
			try {
				search_provider_id = connection.register_object (object_path + "/SearchProvider", search_provider);
			} catch (IOError error) {
				warning ("Could not register search provider service: %s", error.message);
			}
			return true;
		}

		public override void dbus_unregister (DBusConnection connection, string object_path) {
			if (search_provider_id != 0) {
				connection.unregister_object (search_provider_id);
				search_provider_id = 0;
			}
		}

		protected override void activate () {
			base.activate ();
			if (manager_window == null) {
				create_manager_window ();
				manager_window.refresh_packages_list ();
			}
			manager_window.present ();
		}

		protected override int handle_local_options (VariantDict options) {
			if (version) {
				stdout.printf ("Pamac  %s\n", VERSION);
				return 0;
			} else if (updates) {
				try {
					this.register (null);
					this.activate_action ("updates", null);
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			} else if (pkgname != null) {
				try {
					this.register (null);
					this.activate_action ("details", new Variant ("s", pkgname));
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			} else if (app_id != null) {
				try {
					this.register (null);
					this.activate_action ("details-id", new Variant ("s", app_id));
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			} else if (search != null) {
				try {
					this.register (null);
					this.activate_action ("search", new Variant ("s", search));
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			}
			return -1;
		}

		public override void open (File[] files, string hint) {
			// open first file
			unowned File file = files[0];
			#if ENABLE_SNAP
			if (file.has_uri_scheme ("snap")) {
				string app_id = file.get_uri ().replace ("snap:", "").replace ("/", "");
				this.activate_action ("details-id", new Variant ("s", app_id));
				return;
			}
			#endif
			if (file.has_uri_scheme ("appstream")) {
				string app_id = file.get_uri ().replace ("appstream:", "").replace ("/", "");
				this.activate_action ("details-id", new Variant ("s", app_id));
			} else {
				// just open pamac-manager
				this.activate_action ("details", new Variant ("s", ""));
			}
		}

		public override void shutdown () {
			base.shutdown ();
			if (!check_pamac_running () && manager_window != null) {
				// stop system_daemon
				manager_window.transaction.quit_daemon ();
			}
		}

		bool check_pamac_running () {
			Application app;
			bool run = false;
			app = new Application ("org.manjaro.pamac.installer", 0);
			try {
				app.register ();
			} catch (Error e) {
				warning (e.message);
			}
			run = app.get_is_remote ();
			return run;
		}
	}
}

int main (string[] args) {
	var config = new Pamac.Config ("/etc/pamac.conf");
	var database = new Pamac.Database (config);
	var manager = new Pamac.Manager (database);
	// set translated app name
	var appinfo = new DesktopAppInfo ("org.manjaro.pamac.manager.desktop");
	Environment.set_application_name (appinfo.get_name ());
	return manager.run (args);
}
