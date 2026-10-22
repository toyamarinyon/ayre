import Foundation
import XCTest
import AyreCore

final class CLIIntegrationTests: XCTestCase {
    private var executable: URL {
        Bundle(for: CLIIntegrationTests.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ayre")
    }

    private func run(_ arguments: [String], input: Data = Data()) throws -> (Int32, Data, Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return (process.terminationStatus, stdout.fileHandleForReading.readDataToEndOfFile(), stderr.fileHandleForReading.readDataToEndOfFile())
    }

    func testCapabilitiesAndPutPreserveBytesAndEnforceTitleAndNoClobber() throws {
        let capabilities = try run(["capabilities", "--json"])
        XCTAssertEqual(capabilities.0, 0)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: capabilities.1) as? [String: Any])
        XCTAssertEqual(response["protocolVersion"] as? Int, 1)
        XCTAssertEqual(response["version"] as? String, CLIContract.version)
        XCTAssertEqual(response["capabilities"] as? [String], ["put"])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ayre-cli-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("# Hello\r\nbody\n".utf8)
        let args = ["put", "example", "--title", "Hello", "--store", directory.path]
        XCTAssertEqual(try run(args, input: bytes).0, 0)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("example.md")), bytes)
        XCTAssertEqual(try run(args, input: bytes).0, 3)
        XCTAssertEqual(try run(["put", "other", "--title", "Wrong", "--store", directory.path], input: bytes).0, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("other.md").path))

        XCTAssertEqual(try run(args + ["--overwrite"], input: Data([0xFF])).0, 2)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("example.md")), bytes)
        XCTAssertEqual(try run(args + ["--overwrite"], input: Data(repeating: 0x61, count: 1_000_001)).0, 2)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("example.md")), bytes)

        XCTAssertEqual(try run(["put", "example", "--title", "Hello", "--title", "Hello", "--store", directory.path], input: bytes).0, 2)
        XCTAssertEqual(try run(["put", "example", "--title", "Hello", "--overwrite", "--overwrite", "--store", directory.path], input: bytes).0, 2)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("example.md")), bytes)

        let replacement = Data("# Replacement\nnew body".utf8)
        XCTAssertEqual(try run(["put", "example", "--title", "Replacement", "--overwrite", "--store", directory.path], input: replacement).0, 0)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("example.md")), replacement)

        let fileAsDirectory = directory.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: fileAsDirectory)
        XCTAssertEqual(try run(["put", "io", "--title", "IO", "--store", fileAsDirectory.path], input: Data("# IO".utf8)).0, 4)
    }
}
