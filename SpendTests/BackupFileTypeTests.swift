import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Spend

/// 4 Oct 2026, phone run: iOS did not know `.sortdbackup`, so "Keep Both" in
/// Files named a copy "Sortd backup 2026-10-03.sortdbackup 2". The type is
/// now declared in the app's Info.plist and used from one constant.
struct BackupFileTypeTests {

    @Test func theTypeIsDeclaredInTheAppsInfoPlist() throws {
        let declared = try #require(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        let backup = try #require(declared.first { $0["UTTypeIdentifier"] as? String == Backup.typeIdentifier })
        #expect(backup["UTTypeDescription"] as? String == "Sortd Backup")
        let parents = backup["UTTypeConformsTo"] as? [String] ?? []
        #expect(parents.contains("public.data"))
        let tags = backup["UTTypeTagSpecification"] as? [String: Any]
        let ext = tags?["public.filename-extension"] as? [String]
        #expect(ext == [Backup.fileExtension])
    }

    @Test func theConstantNamesTheDeclaredType() {
        #expect(Backup.fileType.identifier == "com.kameshraj.spend.backup")
        #expect(Backup.fileType.conforms(to: .data))
    }

    @Test func theExportedFileNameUsesTheDeclaredExtension() {
        let name = Exports.dated("Sortd backup", Backup.fileExtension)
        #expect(name.hasSuffix(".sortdbackup"))
    }

    @Test func bothPickersOfferTheBackupType() {
        #expect(StatementReader.readableTypes.contains(Backup.fileType))
    }

}
