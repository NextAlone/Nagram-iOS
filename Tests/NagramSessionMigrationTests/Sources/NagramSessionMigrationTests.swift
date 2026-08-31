import XCTest

import TelegramCore

// MARK: NAGRAM — 迁移错误解析的回归测试。
//
// nagramMigrationDatacenterId decides whether an imported session has to be
// moved to another datacenter. Getting it wrong is silent in both directions: a
// missed migration leaves an account that answers nothing, and a spurious one
// throws away a session that was already fine. It is pure, so it is cheap to
// pin down exactly.
final class NagramSessionMigrationTests: XCTestCase {
    func testParsesEveryMigratePrefixTelegramUses() {
        XCTAssertEqual(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "USER_MIGRATE_1"), 1)
        XCTAssertEqual(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "PHONE_MIGRATE_2"), 2)
        XCTAssertEqual(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "NETWORK_MIGRATE_5"), 5)
    }

    func testParsesEveryDatacenterId() {
        for datacenterId in Int32(1) ... Int32(5) {
            XCTAssertEqual(
                nagramMigrationDatacenterId(errorCode: 303, errorDescription: "USER_MIGRATE_\(datacenterId)"),
                datacenterId
            )
        }
    }

    // Only 303 means "you are talking to the wrong datacenter". Everything else
    // is a real failure the caller has to surface, not a migration.
    func testIgnoresOtherErrorCodes() {
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 400, errorDescription: "USER_MIGRATE_2"))
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 401, errorDescription: "AUTH_KEY_UNREGISTERED"))
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 420, errorDescription: "FLOOD_WAIT_30"))
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 0, errorDescription: "USER_MIGRATE_2"))
    }

    func testIgnoresMissingDescription() {
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 303, errorDescription: nil))
    }

    // FILE_MIGRATE redirects one file, not the account, so treating it as a home
    // datacenter change would rebuild the record around the wrong datacenter.
    // Upstream's own matcher (Authorization.swift) excludes it for the same
    // reason.
    func testIgnoresFileMigrate() {
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "FILE_MIGRATE_3"))
    }

    func testIgnoresUnparseableDatacenterId() {
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "USER_MIGRATE_"))
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "USER_MIGRATE_x"))
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "USER_MIGRATE"))
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 303, errorDescription: ""))
    }

    // Upstream force-unwraps the same parse; returning nil instead is what keeps
    // a surprising description from crashing the import.
    func testDoesNotCrashOnTrailingText() {
        XCTAssertNil(nagramMigrationDatacenterId(errorCode: 303, errorDescription: "USER_MIGRATE_2 (retry)"))
    }
}
