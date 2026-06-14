import SwiftUI
import FirebaseAuth

struct SignUpView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSignUpFailed = false
    @State private var isSignedUp = false

    var body: some View {
        NavigationView {
            VStack {
                Text("Sign Up")
                    .font(.largeTitle)
                    .padding()
                
                TextField("Email", text: $email)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if isSignUpFailed {
                    Text("Passwords do not match or an error occurred.")
                        .foregroundColor(.red)
                        .padding()
                }

                Button(action: {
                    signUpUser()
                }) {
                    Text("Sign Up")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding()

                EmptyView()
                    .navigationDestination(isPresented: $isSignedUp) {
                        HomeView()
                    }
                
                NavigationLink(destination: LoginView()) {
                    Text("Already have an account? Log in")
                        .padding()
                        .foregroundColor(.blue)
                }
            }
            .padding()
        }
    }

    func signUpUser() {
        if password == confirmPassword {
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error = error {
                    print("Sign up failed with error: \(error.localizedDescription)")
                    self.isSignUpFailed = true
                } else {
                    // Root switches to HomeView via AuthViewModel in MediaApp
                    self.isSignedUp = true
                    // If this view was presented modally, you could dismiss it:
                    // dismiss()
                }
            }
        } else {
            self.isSignUpFailed = true
        }
    }
}

struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
    }
}
