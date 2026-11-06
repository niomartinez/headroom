import Testing

@Suite struct SandboxTests {
    @Test func containerIDMeansSandboxed() {
        #expect(Sandbox.isActive(environment: ["APP_SANDBOX_CONTAINER_ID": "com.example.app"]))
    }

    @Test func missingOrEmptyContainerIDMeansNotSandboxed() {
        #expect(!Sandbox.isActive(environment: [:]))
        #expect(!Sandbox.isActive(environment: ["APP_SANDBOX_CONTAINER_ID": ""]))
        #expect(!Sandbox.isActive(environment: ["HOME": "/Users/example"]))
    }
}
