import CoreGraphics
import CoachCore

/// Where the coach gets its fields from. Coaching and the rules only ever see
/// FieldSnapshots, so another reader can be added and switched on later
/// without touching them. Today there is one: FocusWatcher (macOS Accessibility).
/// Planned: a terminal-screen reader for legacy apps (3270/5250 emulators) that
/// show the whole screen as one field; it would cut the screen text into
/// virtual fields by row and column, using a screen map per application.
protocol FieldSource: AnyObject {
    /// A field lost the focus: the field, and whether its text changed while it had the focus.
    var onFieldLeft: ((FieldSnapshot, Bool) -> Void)? { get set }
    /// The person clicked a button (such as Start in Jira's Start Sprint dialog) or pressed
    /// Return in a dialog, read just before it takes effect, while the dialog is still there.
    /// Return true to hold the press back (only for a rule set to block with override);
    /// it is called while the press waits, so it must decide quickly.
    var onButtonPressed: ((ButtonPress) -> Bool)? { get set }
    /// The focus moved to another element (any element, not only text fields).
    var onFocusMoved: (() -> Void)? { get set }
    func start()
    /// The field that has the focus right now, for "coach me on this field".
    func currentField() -> FieldSnapshot?
}

/// A button the person clicked, with the dialog it belongs to.
struct ButtonPress {
    /// The label used when the person pressed Return in a dialog field instead of clicking.
    static let returnKey = "Return"

    let label: String
    let pageURL: String?
    /// The text fields of the button's dialog, else empty.
    let form: [FormField]
    /// In a Sprint dialog: reads the Sprint's total estimate from the backlog header on the
    /// page. It walks the whole page, so call it after the press was decided, not while it waits.
    let sprintTotal: () -> Double?
    let frame: CGRect?
}
