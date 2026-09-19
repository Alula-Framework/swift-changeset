import PropertyBased
import Testing

@testable import Changesets

/// The laws dirty tracking obeys, checked over generated edit programs.
///
/// `ChangesetTests` covers these one case at a time — change a field, expect it
/// dirty; change it back, expect it clean. Those are the right tests for the
/// intent. They cannot say anything about the *seventh* edit in a sequence,
/// which is where last-write-wins and revert-detection actually interact, and
/// where a regression would sit unnoticed because nobody writes that example.
///
/// The generated input is a flat array of edits rather than a tree of builder
/// calls, because an array is what the shrinker can take apart: a failure comes
/// back as the two or three edits that still break the law, with a
/// `.fixedSeed(…)` line to replay it exactly.
///
/// Values are drawn from a small pool that *includes each field's original*, so
/// reverts happen by construction rather than by luck — the revert path is the
/// interesting one and a wide random range would almost never hit it.
@Suite("Changeset laws")
struct ChangesetPropertyTests {

    /// One edit. The cases are the fields of `Order`; the values come from a
    /// pool containing the original so `change(_:_:)`'s revert branch runs.
    enum Edit: Sendable, Equatable {
        case customerID(Int)
        case note(String)
        case version(Int)
    }

    static let edits = Gen.frequency(
        (1, Gen.int(in: 1...5).map { Edit.customerID($0) }.eraseToAny()),
        (
            1,
            Gen.element(of: ["leave at door", "ring bell", "hand to resident"])
                .map { Edit.note($0 ?? "ring bell") }.eraseToAny()
        ),
        (1, Gen.int(in: 3...6).map { Edit.version($0) }.eraseToAny())
    ).array(of: 0...12)

    static func apply(_ edits: [Edit], to changeset: Changeset<Order>) -> Changeset<Order> {
        var result = changeset
        for edit in edits {
            switch edit {
            case .customerID(let value): result = result.change(\.customerID, value)
            case .note(let value): result = result.change(\.note, value)
            case .version(let value): result = result.change(\.version, value)
            }
        }
        return result
    }

    /// The last value a program assigns to each field, or nil if it never does.
    static func lastValues(_ edits: [Edit]) -> (customerID: Int?, note: String?, version: Int?) {
        var customerID: Int?
        var note: String?
        var version: Int?
        for edit in edits {
            switch edit {
            case .customerID(let value): customerID = value
            case .note(let value): note = value
            case .version(let value): version = value
            }
        }
        return (customerID, note, version)
    }

    @Test("a field is dirty exactly when its last assigned value differs from the original")
    func dirtyExactlyWhenDifferent() async {
        await propertyCheck(count: 300, input: Self.edits) { edits in
            let original = Order.placed
            let changeset = Self.apply(edits, to: Changeset(original: original))
            let last = Self.lastValues(edits)

            // Never assigned, or assigned back to the original: clean either
            // way. Assigned something else: dirty, and holding that value.
            if let value = last.customerID, value != original.customerID {
                #expect(changeset.changed(\.customerID))
                #expect(changeset.getChange(\.customerID) == value)
            } else {
                #expect(!changeset.changed(\.customerID))
            }
            if let value = last.note, value != original.note {
                #expect(changeset.changed(\.note))
                #expect(changeset.getChange(\.note) == value)
            } else {
                #expect(!changeset.changed(\.note))
            }
            if let value = last.version, value != original.version {
                #expect(changeset.changed(\.version))
                #expect(changeset.getChange(\.version) == value)
            } else {
                #expect(!changeset.changed(\.version))
            }
        }
    }

    @Test("hasChanges agrees with the fields")
    func hasChangesAgrees() async {
        await propertyCheck(count: 300, input: Self.edits) { edits in
            let changeset = Self.apply(edits, to: Changeset(original: Order.placed))
            let anyDirty =
                changeset.changed(\.customerID) || changeset.changed(\.note)
                || changeset.changed(\.version)
            // Two ways of asking the same question must not disagree: one is
            // what a caller branches on, the other is what it renders.
            #expect(changeset.hasChanges == anyDirty)
        }
    }

    @Test("applyChanges yields the original with exactly the recorded changes on it")
    func applyChangesRoundTrip() async {
        await propertyCheck(count: 300, input: Self.edits) { edits in
            let original = Order.placed
            let changeset = Self.apply(edits, to: Changeset(original: original))
            let last = Self.lastValues(edits)
            let applied = changeset.applyChanges(to: original)

            #expect(applied.customerID == (last.customerID ?? original.customerID))
            #expect(applied.note == (last.note ?? original.note))
            #expect(applied.version == (last.version ?? original.version))
            // Untouched by any edit in this program, so it must survive intact.
            #expect(applied.id == original.id)
        }
    }

    @Test("edits to different fields commute")
    func distinctFieldsCommute() async {
        await propertyCheck(count: 300, input: Self.edits) { edits in
            // Reduce to at most one edit per field — within a field, order is
            // meaningful (last write wins) and commuting would be a different
            // claim. Across fields it must not matter.
            let last = Self.lastValues(edits)
            var reduced: [Edit] = []
            if let value = last.customerID { reduced.append(.customerID(value)) }
            if let value = last.note { reduced.append(.note(value)) }
            if let value = last.version { reduced.append(.version(value)) }

            let forward = Self.apply(reduced, to: Changeset(original: Order.placed))
            let backward = Self.apply(reduced.reversed(), to: Changeset(original: Order.placed))
            #expect(forward.applyChanges(to: Order.placed) == backward.applyChanges(to: Order.placed))
            #expect(forward.hasChanges == backward.hasChanges)
        }
    }
}
