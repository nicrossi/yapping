import Testing
@testable import Yapping

struct PermissionsStatusTests {
    @Test func allGrantedRequiresBoth() {
        #expect(!PermissionsStatus(accessibility: true, microphone: .denied).allGranted)
        #expect(!PermissionsStatus(accessibility: false, microphone: .authorized).allGranted)
        #expect(PermissionsStatus(accessibility: true, microphone: .authorized).allGranted)
    }
}
