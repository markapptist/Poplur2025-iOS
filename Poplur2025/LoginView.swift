import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoginFailed = false
    @State private var isLoggedIn = false

    var body: some View {
        NavigationView {  // Wrap the view in NavigationView
            VStack {
                Text("Login")
                    .font(.largeTitle)
                    .padding()
                
                TextField("Email", text: $email)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if isLoginFailed {
                    Text("Invalid email or password. Please try again.")
                        .foregroundColor(.red)
                        .padding()
                }

                Button(action: {
                    loginUser()
                }) {
                    Text("Login")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()

                NavigationLink(destination: SignUpView(), label: {
                    Text("Don't have an account? Sign up")
                        .padding()
                        .foregroundColor(.blue)
                })
            }
            .padding()
            .onAppear {
                checkUserLoggedIn()
            }
            .background(
                NavigationLink(
                    destination: HomeView(),
                    isActive: $isLoggedIn) { EmptyView() }
                    .hidden()
            )  // This creates a hidden navigation link that triggers when isLoggedIn becomes true.
        }
    }

    func loginUser() {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                print("Login failed with error: \(error.localizedDescription)")
                self.isLoginFailed = true
            } else {
                self.isLoggedIn = true
            }
        }
    }

    func checkUserLoggedIn() {
        if Auth.auth().currentUser != nil {
            self.isLoggedIn = true
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
