import SwiftUI

struct ResizeHandle: View {
    let label: String
    let width: CGFloat
    let limits: ClosedRange<CGFloat>
    var multiplier: CGFloat = 1
    let update: (CGFloat) -> Void
    @State private var start: CGFloat?
    @State private var hovering = false

    private func resize(to value: CGFloat) {
        update(min(limits.upperBound, max(limits.lowerBound, value)))
    }

    var body: some View {
        ZStack {
            Color.clear
            Capsule().fill(Color.white.opacity(hovering || start != nil ? 0.54 : 0.22))
                .frame(width: 3, height: 30)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { drag in
                let initial = start ?? width
                start = initial
                resize(to: initial + multiplier * drag.translation.width)
            }
            .onEnded { _ in start = nil })
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(width)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: resize(to: width + 24)
            case .decrement: resize(to: width - 24)
            @unknown default: break
            }
        }
    }
}
