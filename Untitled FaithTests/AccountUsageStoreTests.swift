import XCTest
@testable import Untitled_Faith

@MainActor
final class AccountUsageStoreTests: XCTestCase {
    private var suite: String!
    private var preferences: UserDefaults!

    override func setUp() {
        suite = "usage-tests-\(UUID().uuidString)"
        preferences = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        preferences.removePersistentDomain(forName: suite)
    }

    func testReopeningAndRelaunchingExposeCachedUsageImmediately() async {
        let store = AccountUsageStore(preferences: preferences)
        store.activate(namespace: "backend|one")
        await store.refresh { self.snapshot(80) }?.value
        let restored = AccountUsageStore(preferences: preferences)
        restored.activate(namespace: "backend|one")
        XCTAssertEqual(restored.value?.remainingPercent, 80)
        var calls = 0
        let refresh = restored.refresh { calls += 1; return self.snapshot(60) }
        XCTAssertNil(refresh)
        XCTAssertEqual(calls, 0)
        restored.activate(namespace: "backend|two")
        XCTAssertNil(restored.value)
    }

    func testRefreshKeepsLastKnownValueThroughLoadingAndFailure() async throws {
        let store = AccountUsageStore(preferences: preferences)
        store.activate(namespace: "backend|one")
        await store.refresh { self.snapshot(90) }?.value
        let started = expectation(description: "usage fetch started")
        var continuation: CheckedContinuation<AccountUsage, Error>?
        let task = try XCTUnwrap(store.refresh(force: true) {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        })
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(store.value?.remainingPercent, 90)
        continuation?.resume(throwing: AnswerServiceError.unavailable)
        await task.value
        XCTAssertEqual(store.value?.remainingPercent, 90)
        XCTAssertNotNil(store.errorMessage)
    }

    func testLateResponseFromPreviousAccountCannotOverwriteCurrentUsage() async throws {
        let store = AccountUsageStore(preferences: preferences)
        store.activate(namespace: "backend|one")
        await store.refresh { self.snapshot(90) }?.value
        let started = expectation(description: "old account fetch started")
        var continuation: CheckedContinuation<AccountUsage, Error>?
        let oldTask = try XCTUnwrap(store.refresh(force: true) {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        })
        await fulfillment(of: [started], timeout: 1)
        store.activate(namespace: "backend|two")
        XCTAssertNil(store.value)
        await store.refresh { self.snapshot(40) }?.value
        continuation?.resume(returning: snapshot(80))
        await oldTask.value
        XCTAssertEqual(store.value?.remainingPercent, 40)
        store.activate(namespace: "backend|one")
        XCTAssertEqual(store.value?.remainingPercent, 90)
    }

    func testForcedRefreshDuringLoadingQueuesOnlyOneFollowUp() async throws {
        let store = AccountUsageStore(preferences: preferences)
        store.activate(namespace: "backend|one")
        let started = expectation(description: "initial fetch started")
        var continuation: CheckedContinuation<AccountUsage, Error>?
        var calls = 0
        let load: @MainActor () async throws -> AccountUsage = {
            calls += 1
            if calls == 1 {
                return try await withCheckedThrowingContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
            return self.snapshot(60)
        }
        let first = try XCTUnwrap(store.refresh(load: load))
        await fulfillment(of: [started], timeout: 1)
        store.refresh(force: true, load: load)
        store.refresh(force: true, load: load)
        continuation?.resume(returning: snapshot(80))
        await first.value
        await store.refresh(load: load)?.value
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(store.value?.remainingPercent, 60)
    }

    func testDeletingClearsOnlyTheCurrentAccountCache() async {
        let store = AccountUsageStore(preferences: preferences)
        store.activate(namespace: "backend|one")
        await store.refresh { self.snapshot(80) }?.value
        store.activate(namespace: "backend|two")
        await store.refresh { self.snapshot(40) }?.value
        store.clear(removeCached: true)
        XCTAssertNil(store.value)
        store.activate(namespace: "backend|two")
        XCTAssertNil(store.value)
        store.activate(namespace: "backend|one")
        XCTAssertEqual(store.value?.remainingPercent, 80)
    }

    private func snapshot(_ percent: Int) -> AccountUsage {
        let used = (100 - percent) * 30 / 100
        return AccountUsage(month: "2026-09", resetsAt: "2026-10-01T00:00:00Z", currency: "USD",
            appAccountToken: UUID(), remainingPercent: percent,
            free: .init(monthlyLimit: 30, usedThisMonth: used, remainingThisMonth: 30 - used),
            funding: .init(balanceMicros: 0, reservedMicros: 0, availableMicros: 0),
            usage: .init(totalRequests: used, pendingRequests: 0, promptTokens: 0, completionTokens: 0, costMicros: 0))
    }
}
