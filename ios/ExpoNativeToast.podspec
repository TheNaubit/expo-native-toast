Pod::Spec.new do |s|
  s.name           = 'ExpoNativeToast'
  s.version        = '0.0.0'
  s.summary        = 'Native toasts for Expo'
  s.description    = 'Shows Liquid Glass toasts with an optional action button, semantic haptics, and VoiceOver announcements.'
  s.author         = 'TheNaubit'
  s.homepage       = 'https://github.com/TheNaubit/expo-native-toast'
  s.platforms      = {
    :ios => '16.4'
  }
  s.source         = { git: 'https://github.com/TheNaubit/expo-native-toast.git' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
