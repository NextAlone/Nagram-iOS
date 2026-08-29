import Foundation
import MtProtoKit
import SwiftSignalKit
import TelegramApi

// MARK: NAGRAM — Home datacenter discovery for imported sessions.
//
// A Pyrogram session string records the datacenter its authorization key
// belongs to, which is not necessarily the datacenter the account is homed on.
// Upstream never meets that case: a phone login settles the master datacenter
// while authorizing (PHONE_MIGRATE is handled there), so an authorized
// account's datacenter is right by construction and nothing handles
// USER_MIGRATE afterwards. An imported session can break that invariant, and
// the account then answers every request with USER_MIGRATE_N forever.
//
// These helpers let the importer ask the server where the account actually
// lives and obtain an authorized key for that datacenter. They live here
// because Api and the network plumbing are internal to TelegramCore.

public enum NagramHomeDatacenterProbeResult {
    case current
    case migrate(Int32)
    case failure(errorCode: Int32, errorDescription: String?)
}

public enum NagramAuthenticatedUserProbeResult {
    case userId(Int64)
    case failure(errorCode: Int32, errorDescription: String?)
}

// Returns whether the current master datacenter serves the account, which
// datacenter it should migrate to, or the exact probe failure. Keeping failures
// distinct from success is essential: imported auth keys are untrusted input.
//
// The probe has to be a request only the home datacenter can answer.
// users.getUsers is not: any datacenter will happily return the user, so it
// succeeds on the wrong one and hides the migration. updates.getState reads
// account state, which is exactly what USER_MIGRATE guards.
public func nagramHomeDatacenterId(network: Network) -> Signal<NagramHomeDatacenterProbeResult, NoError> {
    Logger.shared.log("NagramMigration", "probing home datacenter from dc \(network.mtProto.datacenterId)")
    let requestService = network.requestService
    let data = Api.functions.updates.getState()
    // Deliberately not Network.request: its shouldContinueExecutionWithErrorContext
    // returns true, so MTProto keeps retrying the request forever and the error
    // is never delivered. That is right for ordinary traffic and fatal here,
    // because the USER_MIGRATE response *is* the answer this probe wants.
    return Signal<NagramHomeDatacenterProbeResult, NoError> { subscriber in
        let request = MTRequest()
        request.setPayload(
            data.1.makeData() as Data,
            metadata: WrappedRequestMetadata(metadata: WrappedFunctionDescription(data.0), tag: nil),
            shortMetadata: WrappedRequestShortMetadata(shortMetadata: WrappedShortFunctionDescription(data.0)),
            responseParser: { response in
                if let result = data.2.parse(Buffer(data: response)) {
                    return BoxedMessage(result)
                }
                return nil
            }
        )
        request.dependsOnPasswordEntry = false
        request.shouldContinueExecutionWithErrorContext = { _ in
            return false
        }
        request.completed = { (_, _, error) -> Void in
            if let error = error {
                let resolved = nagramMigrationDatacenterId(errorCode: error.errorCode, errorDescription: error.errorDescription)
                Logger.shared.log("NagramMigration", "probe error \(error.errorCode) \(error.errorDescription ?? "nil") -> home dc \(resolved.flatMap { "\($0)" } ?? "unknown")")
                if let resolved {
                    subscriber.putNext(.migrate(resolved))
                } else {
                    subscriber.putNext(.failure(errorCode: error.errorCode, errorDescription: error.errorDescription))
                }
            } else {
                Logger.shared.log("NagramMigration", "probe succeeded: this datacenter already serves the account")
                subscriber.putNext(.current)
            }
            subscriber.putCompletion()
        }
        let internalId: Any! = request.internalId
        requestService.add(request)
        Logger.shared.log("NagramMigration", "probe request submitted")
        return ActionDisposable { [weak requestService] in
            Logger.shared.log("NagramMigration", "probe disposed (cancelled before completing)")
            requestService?.removeRequest(byInternalId: internalId)
        }
    }
}

// Verifies the identity authenticated by an imported key. The user id in a
// Pyrogram session string is not integrity-protected, so it must never be
// trusted as the account peer id without comparing it to users.getUsers(self).
// A raw non-retrying request makes invalid-key and transport failures explicit
// instead of leaving the staging account alive indefinitely.
public func nagramAuthenticatedUserId(network: Network) -> Signal<NagramAuthenticatedUserProbeResult, NoError> {
    Logger.shared.log("NagramMigration", "verifying authenticated self user")
    let requestService = network.requestService
    let data = Api.functions.users.getUsers(id: [.inputUserSelf])
    return Signal<NagramAuthenticatedUserProbeResult, NoError> { subscriber in
        let request = MTRequest()
        request.setPayload(
            data.1.makeData() as Data,
            metadata: WrappedRequestMetadata(metadata: WrappedFunctionDescription(data.0), tag: nil),
            shortMetadata: WrappedRequestShortMetadata(shortMetadata: WrappedShortFunctionDescription(data.0)),
            responseParser: { response in
                if let result = data.2.parse(Buffer(data: response)) {
                    return BoxedMessage(result)
                }
                return nil
            }
        )
        request.dependsOnPasswordEntry = false
        request.shouldContinueExecutionWithErrorContext = { _ in
            return false
        }
        request.completed = { (boxedResponse, _, error) -> Void in
            if let error {
                Logger.shared.log("NagramMigration", "self-user verification failed: \(error.errorCode) \(error.errorDescription ?? "nil")")
                subscriber.putNext(.failure(errorCode: error.errorCode, errorDescription: error.errorDescription))
            } else if let users = (boxedResponse as? BoxedMessage)?.body as? [Api.User], let apiUser = users.first {
                let userId: Int64
                switch apiUser {
                case let .user(userData):
                    userId = userData.id
                case let .userEmpty(userEmptyData):
                    userId = userEmptyData.id
                }
                Logger.shared.log("NagramMigration", "authenticated self user is \(userId)")
                subscriber.putNext(.userId(userId))
            } else {
                Logger.shared.log("NagramMigration", "self-user verification returned no parseable user")
                subscriber.putNext(.failure(errorCode: 500, errorDescription: "SELF_USER_NOT_RETURNED"))
            }
            subscriber.putCompletion()
        }
        let internalId: Any! = request.internalId
        requestService.add(request)
        return ActionDisposable { [weak requestService] in
            requestService?.removeRequest(byInternalId: internalId)
        }
    }
}

// Parses "USER_MIGRATE_2" and friends. Exposed for testing.
public func nagramMigrationDatacenterId(errorCode: Int32, errorDescription: String?) -> Int32? {
    guard errorCode == 303, let errorDescription else {
        return nil
    }
    for prefix in ["USER_MIGRATE_", "PHONE_MIGRATE_", "NETWORK_MIGRATE_"] {
        if let range = errorDescription.range(of: prefix) {
            return Int32(errorDescription[range.upperBound...])
        }
    }
    return nil
}

// A key alone is not enough. Creating a key for a datacenter is a plain
// Diffie-Hellman handshake and leaves it *unauthorized*; authorizing it means
// transferring authorization from a datacenter that already is, which MTProto
// starts from a separate entry point (authTokenForDatacenter). Promoting an
// unauthorized key to master would sign the account out, so the auth token is
// what this waits on, not just the key.
private func nagramAuthorizedPersistentKey(_ network: Network, _ datacenterId: Int) -> (key: Data, keyId: Int64)? {
    guard network.context.authTokenForDatacenter(withId: datacenterId) != nil else {
        return nil
    }
    guard let info = network.context.authInfoForDatacenter(withId: datacenterId, selector: .persistent), let key = info.authKey else {
        return nil
    }
    return (key, info.authKeyId)
}

// Obtains an authorized persistent key on `datacenterId`, transferring
// authorization from `masterDatacenterId`. That direction is why the imported
// session's own datacenter has to still be the master when this runs: it is the
// one Telegram already accepts. Polls because both steps complete
// asynchronously.
public func nagramAuthorizedDatacenterKey(network: Network, datacenterId: Int32, masterDatacenterId: Int32, remainingAttempts: Int = 30) -> Signal<(key: Data, keyId: Int64)?, NoError> {
    let identifier = Int(datacenterId)
    if let existing = nagramAuthorizedPersistentKey(network, identifier) {
        return .single(existing)
    }
    network.context.performBatchUpdates({
        if network.context.authInfoForDatacenter(withId: identifier, selector: .persistent) == nil {
            network.context.authInfoForDatacenter(withIdRequired: identifier, isCdn: false, selector: .persistent, allowUnboundEphemeralKeys: false)
        }
    })
    network.context.authTokenForDatacenter(withIdRequired: identifier, authToken: identifier as NSNumber, masterDatacenterId: Int(masterDatacenterId))
    if remainingAttempts % 10 == 0 {
        let hasKey = network.context.authInfoForDatacenter(withId: identifier, selector: .persistent) != nil
        let hasToken = network.context.authTokenForDatacenter(withId: identifier) != nil
        Logger.shared.log("NagramMigration", "awaiting dc \(identifier) authorization from dc \(masterDatacenterId): key=\(hasKey) token=\(hasToken) attemptsLeft=\(remainingAttempts)")
    }
    if remainingAttempts <= 0 {
        Logger.shared.log("NagramMigration", "gave up authorizing dc \(identifier)")
        return .single(nil)
    }
    return Signal<Void, NoError>.single(Void())
    |> delay(1.0, queue: Queue.concurrentDefaultQueue())
    |> mapToSignal { _ -> Signal<(key: Data, keyId: Int64)?, NoError> in
        if let found = nagramAuthorizedPersistentKey(network, identifier) {
            return .single(found)
        }
        return nagramAuthorizedDatacenterKey(network: network, datacenterId: datacenterId, masterDatacenterId: masterDatacenterId, remainingAttempts: remainingAttempts - 1)
    }
}
