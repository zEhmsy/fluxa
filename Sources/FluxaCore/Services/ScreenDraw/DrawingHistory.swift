import Foundation

// MARK: - DrawingHistory

/// Manages undo/redo stacks, eraser removal, and disappearing ink expiration.
package final class DrawingHistory: @unchecked Sendable {

    package enum HistoryAction: Equatable, Sendable {
        case add(DrawingStroke)
        case clear([DrawingStroke])
    }

    private let lock = NSLock()
    private var _strokes: [DrawingStroke] = []
    private var _undoStack: [HistoryAction] = []
    private var _redoStack: [HistoryAction] = []

    package init(initialStrokes: [DrawingStroke] = []) {
        self._strokes = initialStrokes
        self._undoStack = initialStrokes.map { .add($0) }
    }

    package var strokes: [DrawingStroke] {
        lock.lock()
        defer { lock.unlock() }
        return _strokes
    }

    package var canUndo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_undoStack.isEmpty
    }

    package var canRedo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_redoStack.isEmpty
    }

    /// Adds a newly completed stroke to history, clearing the redo stack.
    package func addStroke(_ stroke: DrawingStroke) {
        lock.lock()
        defer { lock.unlock() }
        _strokes.append(stroke)
        _undoStack.append(.add(stroke))
        _redoStack.removeAll()
    }

    /// Undoes the last stroke or batch action and returns the affected stroke, or nil if history is empty.
    @discardableResult
    package func undo() -> DrawingStroke? {
        lock.lock()
        defer { lock.unlock() }
        guard let action = _undoStack.popLast() else { return nil }
        switch action {
        case .add(let stroke):
            _strokes.removeAll(where: { $0.id == stroke.id })
            _redoStack.append(.add(stroke))
            return stroke
        case .clear(let batch):
            _strokes.append(contentsOf: batch)
            _redoStack.append(.clear(batch))
            return batch.last
        }
    }

    /// Redoes the most recently undone action and returns the affected stroke, or nil if redo stack is empty.
    @discardableResult
    package func redo() -> DrawingStroke? {
        lock.lock()
        defer { lock.unlock() }
        guard let action = _redoStack.popLast() else { return nil }
        switch action {
        case .add(let stroke):
            _strokes.append(stroke)
            _undoStack.append(.add(stroke))
            return stroke
        case .clear(let batch):
            let batchIDs = Set(batch.map(\.id))
            _strokes.removeAll(where: { batchIDs.contains($0.id) })
            _undoStack.append(.clear(batch))
            return batch.last
        }
    }

    /// Removes all strokes intersecting with a target point (eraser tool).
    @discardableResult
    package func erase(at point: DrawingPoint, radius: Double) -> [DrawingStroke] {
        lock.lock()
        defer { lock.unlock() }
        var removed: [DrawingStroke] = []
        _strokes.removeAll { stroke in
            if stroke.contains(point: point, threshold: radius) {
                removed.append(stroke)
                return true
            }
            return false
        }
        if !removed.isEmpty {
            _undoStack.removeAll(where: { action in
                if case .add(let stroke) = action {
                    return removed.contains(where: { $0.id == stroke.id })
                }
                return false
            })
            _redoStack.removeAll()
        }
        return removed
    }

    /// Clears all strokes. Cleared strokes are pushed to undo stack and can be restored via undo().
    @discardableResult
    package func clear() -> [DrawingStroke] {
        lock.lock()
        defer { lock.unlock() }
        guard !_strokes.isEmpty else { return [] }
        let cleared = _strokes
        _strokes.removeAll()
        _undoStack.append(.clear(cleared))
        _redoStack.removeAll()
        return cleared
    }

    /// Prunes strokes that have exceeded the timeout duration for disappearing ink.
    /// Returns the IDs of removed strokes.
    @discardableResult
    package func pruneExpired(currentTime: Date = Date(), timeout: TimeInterval) -> [UUID] {
        guard timeout > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var expiredIDs: [UUID] = []
        _strokes.removeAll { stroke in
            if stroke.isExpired(at: currentTime, timeout: timeout) {
                expiredIDs.append(stroke.id)
                return true
            }
            return false
        }
        return expiredIDs
    }
}
