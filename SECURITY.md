# Security and privacy

The plugin and helper run as the logged-in user, without an additional sandbox. Device configuration requires HID access; software actions can send shortcuts to applications. Review code before installing or updating it, and do not run it as root.

Never commit real device configurations or runtime snapshots. These may contain serials, Bluetooth addresses, paired-host names, application classes and shortcut assignments. Screenshots can expose unrelated desktop content. Redact reports and use synthetic fixtures in tests. Git ignore rules are only a convenience: they do not remove tracked files or erase history.

Before publishing, inspect `git diff --cached`, tracked files, commit messages and author email settings. No automated check here guarantees that a repository is free of secrets. If sensitive data was committed, removing the current file is insufficient; address exposed credentials and history before publication.

For a security issue, use the repository host’s private vulnerability reporting facility if enabled. Do not open a public issue containing secrets, unredacted diagnostics or exploit details. There is no dedicated private reporting address configured by this project yet.
