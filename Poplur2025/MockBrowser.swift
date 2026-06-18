import SwiftUI

public struct MockBrowser<Content: View>: View {
    public let urlString: String
    public let content: Content
    
    public init(urlString: String, @ViewBuilder content: () -> Content) {
        self.urlString = urlString
        self.content = content()
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            addressBar
            Divider()
            ScrollView {
                content
                    .padding()
            }
            .background(Color.white)
        }
        .background(Color(white: 0.95))
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding()
    }
    
    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
            Circle()
                .fill(Color.yellow)
                .frame(width: 12, height: 12)
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(white: 0.85))
        .cornerRadius(8, corners: [.topLeft, .topRight])
    }
    
    private var addressBar: some View {
        HStack(spacing: 12) {
            Button(action: {}, label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.gray)
                    .font(.system(size: 16, weight: .semibold))
            })
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {}, label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.system(size: 16, weight: .semibold))
            })
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {}, label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.gray)
                    .font(.system(size: 16, weight: .semibold))
            })
            .buttonStyle(PlainButtonStyle())
            
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(Color.green)
                Text(urlString)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.9))
            .cornerRadius(12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.9))
    }
}

// MARK: - Helper for rounding specific corners

fileprivate extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

fileprivate struct RoundedCorner: Shape {
    var radius: CGFloat = 8.0
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct MockBrowser_Previews: PreviewProvider {
    static var previews: some View {
        MockBrowser(urlString: "https://www.example.com") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to the Mock Browser")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("This is placeholder content inside the mock browser window. Scroll to see more content.")
                
                ForEach(0..<20) { i in
                    Text("Item \(i + 1)")
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
        .frame(maxWidth: 600, maxHeight: 500)
    }
}
