import AppKit
import SwiftUI

let ember = Color(red: 0.93, green: 0.24, blue: 0.055)

struct GlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct GlassSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background { ZStack { GlassMaterial(); Color(red: 1, green: 0.76, blue: 0.51).opacity(0.12) } }
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.45), lineWidth: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .foregroundStyle(Color(red: 0.22, green: 0.16, blue: 0.12))
            .tint(ember)
            .environment(\.colorScheme, .light)
    }
}

struct ToastView: View {
    let title: String
    let subtitle: String
    let progress: Bool
    var onClick: () -> Void
    var body: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: progress ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill").foregroundStyle(ember)
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                }
                Text(subtitle).font(.system(size: 10)).opacity(0.65).lineLimit(1).truncationMode(.middle)
                if progress { ProgressView().progressViewStyle(.linear).controlSize(.mini).tint(ember) }
            }
            .padding(.horizontal, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle()).onTapGesture { if !progress { onClick() } }
        }
    }
}

struct WelcomeView: View {
    let onChoose: () -> Void
    let onClose: () -> Void
    var body: some View {
        GlassSurface {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
                    Spacer()
                    Text("ShiftDrop").font(.system(size: 13, weight: .semibold))
                    Spacer(); Color.clear.frame(width: 24, height: 24)
                }.padding(14)
                ZStack {
                    ForEach(0..<8) { index in
                        RoundedRectangle(cornerRadius: 9).fill(ember.opacity(index == 2 ? 0.95 : 0.12))
                            .frame(width: 29, height: 30).offset(y: -48).rotationEffect(.degrees(Double(index) * 45))
                    }
                    Image(systemName: "arrow.up.document.fill").font(.system(size: 25)).foregroundStyle(ember)
                }.frame(height: 132)
                Text("A little shift. A new format.").font(.system(size: 22, weight: .semibold, design: .rounded)).padding(.top, 3)
                Text("Drag a file. Press Shift. Drop to convert.")
                    .font(.system(size: 13)).opacity(0.75).padding(.top, 10)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Press Shift again for image tools.", systemImage: "shift")
                    Label("Your new file appears beside the original.", systemImage: "doc.on.doc")
                    Label("Everything happens on your Mac.", systemImage: "lock")
                }.font(.system(size: 11.5)).opacity(0.75).padding(.vertical, 24)
                Button("Choose a File…", action: onChoose).buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                Text("Always here in your menu bar").font(.system(size: 10)).opacity(0.45).padding(.top, 13)
                Spacer(minLength: 16)
            }
        }
    }
}
