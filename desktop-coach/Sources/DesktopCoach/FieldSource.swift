/// Where the coach gets its fields from. Coaching and the rules only ever see
/// FieldSnapshots, so another reader can be added and switched on later
/// without touching them. Today there is one: FocusWatcher (macOS Accessibility).
/// Planned: a terminal-screen reader for legacy apps (3270/5250 emulators) that
/// show the whole screen as one field; it would cut the screen text into
/// virtual fields by row and column, using a screen map per application.
protocol FieldSource: AnyObject {
    /// A field lost the focus: the field, whether its text changed while it had the focus,
    /// and the label of the field that got the focus next (nil when there is none).
    var onFieldLeft: ((FieldSnapshot, Bool, String?) -> Void)? { get set }
    func start()
    /// The field that has the focus right now, for "coach me on this field".
    func currentField() -> FieldSnapshot?
}
