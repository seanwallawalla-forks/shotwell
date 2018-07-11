public class ImportRoll.Branch : Sidebar.Branch {
    private Gee.HashMap<int64?, ImportRoll.SidebarEntry> entries;

    internal const string HANDLE = "import-roll";

    public class Branch() {
        base (new ImportRoll.Root(), Branch.HANDLE,
              Sidebar.Branch.Options.HIDE_IF_EMPTY,
              ImportRoll.Branch.comparator);

        this.entries = new Gee.HashMap<int64?, ImportRoll.SidebarEntry>(int64_hash, int64_equal);

        foreach (var source in MediaCollectionRegistry.get_instance().get_all()) {
            on_import_rolls_altered(source);
            source.import_roll_altered.connect(on_import_rolls_altered);
        }

    }

    private static int comparator(Sidebar.Entry a, Sidebar.Entry b) {
        if (a == b)
            return 0;

        var entry_a = (ImportRoll.SidebarEntry) a;
        var entry_b = (ImportRoll.SidebarEntry) b;

        return -ImportID.compare_func(entry_a.get_id(), entry_b.get_id());
    }

    private void on_import_rolls_altered(MediaSourceCollection source) {
        var ids = source.get_import_roll_ids();
        foreach (var id in ids) {
            if (!this.entries.has_key (id.id)) {
                var entry = new ImportRoll.SidebarEntry(id);
                entries.set(id.id, entry);
                graft(get_root(), entry);
            }
        }
    }
}

private class ImportRoll.Root : Sidebar.Header {
    public Root() {
        base (Resources.map_subtree_name(Branch.HANDLE), _("Browse the library’s import history"));
    }
}
