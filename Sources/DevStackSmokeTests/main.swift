import DevStackCore

@main
struct DevStackSmokeTests {
    static func main() throws {
        try DevStackSmokeChecks.runAll()
        print("Smoke tests passed.")
    }
}
