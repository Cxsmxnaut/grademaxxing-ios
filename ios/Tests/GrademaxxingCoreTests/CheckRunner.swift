import Foundation

struct CheckFailure: Error, CustomStringConvertible {
  let description: String
}
func expect(_ condition: Bool, file: StaticString = #fileID, line: UInt = #line) throws {
  if !condition { throw CheckFailure(description: "Expectation failed at \(file):\(line)") }
}
func require<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
  guard let value else {
    throw CheckFailure(description: "Required value missing at \(file):\(line)")
  }
  return value
}
func expectThrows<T, E: Error & Equatable>(_ error: E, operation: () throws -> T) throws {
  do { _ = try operation() } catch let actual as E {
    try expect(actual == error)
    return
  } catch { throw CheckFailure(description: "Unexpected error type") }
  throw CheckFailure(description: "Expected operation to throw")
}
func expectThrows<T, E: Error & Equatable>(_ error: E, operation: () async throws -> T) async throws
{
  do { _ = try await operation() } catch let actual as E {
    try expect(actual == error)
    return
  } catch { throw CheckFailure(description: "Unexpected error type") }
  throw CheckFailure(description: "Expected operation to throw")
}

@main enum CheckRunner {
  static func main() async throws {
    var count = 0
    func check(_ name: String, _ operation: () async throws -> Void) async throws {
      try await operation()
      count += 1
      print("PASS \(name)")
    }
    try await check("assignment parsing, simulations, targets, and trend match web rules") {
      try AssignmentPlanningTests.matchesWebAssignmentRules()
    }
    try await check("invalid edited points and unavailable original evidence") {
      try AssignmentPlanningTests.invalidEditsAndUnsupportedEvidenceStayDistinct()
    }
    try await check("backend XML contract, raw versus weighted points") {
      try GradebookTests.decodesRealBackendBuilderContract()
    }
    try await check("official grades and first mark preservation") {
      try GradebookTests.preservesOfficialPercentInsteadOfInferringRawScore()
    }
    try await check("empty and summary response handling") {
      try GradebookTests.handlesEmptyAndSummaryGradebooks()
    }
    for xml in [
      "<html/>", "<Gradebook>",
      "<!DOCTYPE Gradebook [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><Gradebook/>",
      "<Gradebook><ReportingPeriod Index=\"-1\"/><Courses/></Gradebook>",
    ] {
      try await check("invalid XML and entity rejection") {
        try GradebookTests.rejectsInvalidAndExternalEntityXML(xml)
      }
    }
    try await check("non-JSON response rejection") { try GradebookTests.rejectsNonJSONResponse() }
    try await check("duplicate record rejection") {
      try GradebookTests.rejectsDuplicateAssignmentIDs()
    }
    try await check("weighted category projection") {
      try PlanningTests.weightedProjectionUsesCategoryTotalsAndLeavesOfficialMarkUnchanged()
    }
    try await check("unreliable projection refusal") {
      try PlanningTests.refusesUnreliableBaselineAndUnknownWeights()
    }
    try await check("extra credit and invalid numeric inputs") {
      try PlanningTests.extraCreditIsAllowedButInvalidInputsAreRejected()
    }
    try await check("provisional GPA policy and credits") {
      try PlanningTests.gpaMatchesProvisionalWebPolicyAndCreditWeighting()
    }
    try await check("login, session header, rotation, password non-persistence") {
      try await APITests.loginAndRotatedCookieUseExactBackendHeaders()
    }
    try await check("invalid restored session cleanup") {
      try await APITests.restoresAndClearsInvalidSession()
    }
    try await check("upstream expiry versus app expiry") {
      try await APITests.distinguishesDistrictExpiryFromAppExpiry()
    }
    try await check("offline logout clears local vault") {
      try await APITests.logoutClearsVaultEvenWhenRemoteServiceFails()
    }
    try await check("reporting-period requests serialized across suspension") {
      try await APITests.concurrentPeriodRequestsStaySerializedAcrossAwaits()
    }
    try await check("origin isolation") {
      try await APITests.doesNotReuseSessionAcrossServiceOrigins()
    }
    for value in [
      "http://synthetic.example", "https://user:password@synthetic.example",
      "https://synthetic.example/api", "https://synthetic.example?token=fake",
    ] {
      try await check("unsafe configuration rejection") {
        try APITests.rejectsUnsafeServiceConfiguration(value)
      }
    }
    try await check("failed reconnect preserves current session") {
      try await APITests.failedReauthenticationPreservesCurrentSession()
    }
    try await check("redirect and insecure cookie rejection") {
      try await APITests.rejectsRedirectAndDoesNotPersistInsecureCookie()
    }
    try await check("attendance matches backend and excludes holidays/future/weekends") {
      try SchoolTests.normalizedAttendanceMatchesBackendAndExcludesNonSchoolDays()
    }
    try await check("period incidents override daily presence") {
      try SchoolTests.authoritativePeriodIncidentOverridesDailyPresence()
    }
    try await check("unknown and unexcused tardy statuses") {
      try SchoolTests.statusRecognitionPreservesUnknownAndUnexcusedTardy()
    }
    try await check("invalid attendance date and totals rejection") {
      try SchoolTests.rejectsInvalidAttendanceDatesAndNegativeTotals()
    }
    try await check("school dates, leap years, and strict ISO") {
      try SchoolTests.schoolDatesHandleLeapYearsAndStrictISO()
    }
    try await check("calendar month navigation and API bounds") {
      try SchoolTests.calendarMonthNavigationHonorsAPIYearLimits()
    }
    try await check("calendar filtering and distinct event occurrences") {
      try SchoolTests.calendarFiltersMonthAndKeepsDuplicateEventOccurrencesDistinct()
    }
    try await check("calendar invalid date rejection") {
      try SchoolTests.calendarRejectsInvalidEventDates()
    }
    try await check("synthetic school demo contract decoding") {
      try SchoolTests.everySchoolDemoUsesRealDecoders()
    }
    try await check("in-flight records cleared by sign-out") {
      try await RecordStoreTests.invalidationIgnoresInFlightRecordAfterSignOut()
    }
    try await check("old records cannot replace a new account/month") {
      try await RecordStoreTests.anOldRecordCannotReplaceNewAccountOrMonth()
    }
    try await check("cached reads, forced refresh, and failure preservation") {
      try await RecordStoreTests.cachedReadsAndForcedRefreshHaveSeparateBehavior()
    }
    try await check("school resources use authenticated read-only routes") {
      try await APITests.schoolResourcesUseAuthenticatedReadOnlyRoutes()
    }
    try await check("sign-out clears session before a slow read finishes") {
      try await APITests.logoutDeletesSessionBeforeAnInFlightReadFinishes()
    }
    try await check("a late login cannot restore a signed-out session") {
      try await APITests.aLateLoginCannotRestoreSessionAfterLogout()
    }
    try await check("documents match the actual backend adapter") {
      try DocumentsMailTests.documentsMatchActualAdapterAndHandleEmptyLists()
    }
    try await check("mail folders, message details, and official unread flags") {
      try DocumentsMailTests.mailboxPreservesFolderAndUnreadFlags()
    }
    try await check("invalid message identifiers retain a visible summary") {
      try DocumentsMailTests.invalidMessageIDsStayVisibleButCannotBeOpened()
    }
    try await check("native message text, blocked active HTML, and explicit links") {
      try DocumentsMailTests.nativeTextRemovesActiveHTMLAndExposesOnlySafeLinks()
    }
    try await check("message bounds and incomplete active markup") {
      try DocumentsMailTests.bodyBoundsAndUnclosedScriptsAreHandled()
    }
    try await check("real synthetic PDF validation and filename containment") {
      try DocumentsMailTests.syntheticPDFValidatesAndUntrustedFilenameIsContained()
    }
    try await check("base64 bounds and active file format rejection") {
      try DocumentsMailTests.base64AndActiveContentRejection()
    }
    try await check("image signatures, dimensions, and declared MIME fidelity") {
      try DocumentsMailTests.pngSignatureAndDimensionsAreValidated()
    }
    try await check("private preview copies and replacement cleanup") {
      try PreviewLifecycleTests.previewCopiesArePrivateAndReplacedCopiesAreRemoved()
    }
    try await check("relaunch cleanup of orphaned previews") {
      try PreviewLifecycleTests.relaunchPurgesOrphanedPreviewFiles()
    }
    try await check("preview storage rejects arbitrary paths and symlinks") {
      try PreviewLifecycleTests.arbitraryDirectoriesAndSymlinkRootsAreRejected()
    }
    try await check("a dismissed download cannot create a preview copy") {
      try await PreviewLifecycleTests.dismissedDownloadCannotCreateAPreviewCopy()
    }
    try await check("closing preview removes file and private title") {
      try await PreviewLifecycleTests.closeDeletesAnOpenedPreviewAndDropsItsName()
    }
    try await check("real URLSession streaming cap without Content-Length") {
      try await BoundedTransportTests.streamedResponsesHonorCapsWithoutContentLength()
    }
    try await check("advertised response size cap") {
      try await BoundedTransportTests.advertisedOversizeResponsesAreRejected()
    }
    try await check("exact response size boundary") {
      try await BoundedTransportTests.exactResponseBoundarySucceeds()
    }
    try await check("documents/mail routes, session headers, and encoded identifiers") {
      try await APITests.documentsAndMailUseReadOnlyRoutesAndEncodedIdentifiers()
    }
    try await check("malformed message/attachment IDs fail before networking") {
      try await APITests.malformedMessageAndAttachmentIDsNeverReachTheTransport()
    }
    try await check("preview cleanup failures are reported without following symlinks") {
      try await PreviewLifecycleTests.cleanupFailureRemainsVisibleAndDoesNotFollowSymlinks()
    }
    try await check("GPA policy parity with the actual web functions") {
      try GradeParityTests.gpaMatchesTheOwningWebModule()
    }
    try await check("automatic refresh preserves edited plans and updates defaults") {
      try GradeParityTests.automaticRefreshPreservesEditedPlansAndUpdatesUntouchedDefaults()
    }
    try await check("unpublished marks and GPA display rounding") {
      try GradeParityTests.unpublishedGradesDoNotSilentlyEnterTheGPA()
    }
    try await check("unchanged headers reuse details without extending full-read age") {
      try await GradebookRepositoryTests.unchangedHeadersReuseAssignmentsWithoutExtendingFullReadAge()
    }
    try await check("changed marks force full gradebook retrieval") {
      try await GradebookRepositoryTests.changedMarksForceCompleteRetrieval()
    }
    try await check("missing percentages and structural changes reject cache reuse") {
      try GradebookRepositoryTests.missingPercentageAndStructuralChangesCannotReuseDetails()
    }
    try await check("full-refresh deadline and explicit refresh") {
      try await GradebookRepositoryTests
        .thirtyMinuteDeadlineAndExplicitRefreshAlwaysUseCompleteReads()
    }
    try await check("summary fallback full response is accepted") {
      try await GradebookRepositoryTests.summaryFallbackCompleteResponseIsAccepted()
    }
    try await check("gradebook session isolation") {
      try await GradebookRepositoryTests.sessionChangesRemovePreviousRecords()
    }
    try await check("bounded gradebook cache and actual returned period") {
      try await GradebookRepositoryTests.cacheIsBoundedAndUsesReceivedPeriod()
    }
    try await check("old responses cannot repopulate cleared gradebooks") {
      try await GradebookRepositoryTests.clearedCacheCannotBeRepopulatedByAnOldResponse()
    }
    try await check("summary API reads have no fresh override") {
      try await APITests.summaryReadHasNoFreshOverride()
    }
    print("\(count) synthetic checks passed. No live school requests were made.")
  }
}
