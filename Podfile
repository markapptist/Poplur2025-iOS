platform :ios, '15.0'
use_frameworks!

target 'Poplur2025' do
  # Firebase (already present via SPM is fine; you can keep SPM for Firebase if you prefer)
  # pod 'Firebase/Auth'
  # pod 'Firebase/Firestore'
  # pod 'Firebase/Storage'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      # Ensure modules are built as frameworks and enable library evolution if needed
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
