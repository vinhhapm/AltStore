//
//  AppVersion.swift
//  AltStoreCore
//
//  Created by Riley Testut on 8/18/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

@objc(AppVersion)
public class AppVersion: NSManagedObject, Decodable, Fetchable
{
    /* Properties */
    @NSManaged public var version: String
    @NSManaged public var marketingVersion: String?
    
    // NULL does not work as expected with SQL Unique Constraints (because NULL != NULL),
    // so we store non-optional value and provide public accessor with optional return type.
    @nonobjc public var buildVersion: String? {
        get { _buildVersion.isEmpty ? nil : _buildVersion }
        set { _buildVersion = newValue ?? "" }
    }
    @NSManaged @objc(buildVersion) public private(set) var _buildVersion: String
    
    @NSManaged public var date: Date
    @NSManaged public var localizedDescription: String?
    @NSManaged public var size: Int64
    @NSManaged public var sha256: String?
    
    @NSManaged public var downloadURL: URL
    @NSManaged public internal(set) var normalizedDownloadURL: String?
    @NSManaged public internal(set) var assetURLs: [String: URL]?
    
    @nonobjc public var minOSVersion: OperatingSystemVersion? {
        guard let osVersionString = self._minOSVersion else { return nil }
        
        let osVersion = OperatingSystemVersion(string: osVersionString)
        return osVersion
    }
    @NSManaged @objc(minOSVersion) private var _minOSVersion: String?
    
    @nonobjc public var maxOSVersion: OperatingSystemVersion? {
        guard let osVersionString = self._maxOSVersion else { return nil }
        
        let osVersion = OperatingSystemVersion(string: osVersionString)
        return osVersion
    }
    @NSManaged @objc(maxOSVersion) private var _maxOSVersion: String?
    
    @NSManaged public var appBundleID: String
    @NSManaged public var sourceID: String?
    
    /* Relationships */
    @NSManaged public private(set) var app: StoreApp?
    @NSManaged @objc(latestVersionApp) public internal(set) var latestSupportedVersionApp: StoreApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    internal enum CodingKeys: String, CodingKey
    {
        case version
        case buildVersion
        case marketingVersion
        case date
        case localizedDescription
        case downloadURL
        case assetURLs
        case size
        case sha256
        case minOSVersion
        case maxOSVersion
        
        // Localized
        case localizedDescriptions
        
        // Legacy
        case legacyLocalizedDescriptions = "_localizedDescriptions"
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppVersion.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.version = try container.decode(String.self, forKey: .version)
            self.buildVersion = try container.decodeIfPresent(String.self, forKey: .buildVersion)
            self.marketingVersion = try container.decodeIfPresent(String.self, forKey: .marketingVersion)
            
            self.date = try container.decode(Date.self, forKey: .date)
            
            if let localizedDescription = try container.decodeLocalizedValue(String.self, forKey: .localizedDescriptions) ?? container.decodeLocalizedValue(String.self, forKey: .legacyLocalizedDescriptions)
            {
                self.localizedDescription = localizedDescription
            }
            else
            {
                self.localizedDescription = try container.decodeIfPresent(String.self, forKey: .localizedDescription)
            }
            
            var downloadURL = try container.decode(URL.self, forKey: .downloadURL)
            
            #if MARKETPLACE
            
            if downloadURL.lastPathComponent.lowercased() == "manifest.json"
            {
                // Special-case providing the ADP's manifest's URL instead of the ADP directory itself.
                downloadURL.deleteLastPathComponent()
            }
            
            // Remove trailing slash if it exists.
            let lastComponent = downloadURL.lastPathComponent
            downloadURL = downloadURL.deletingLastPathComponent().appendingPathComponent(lastComponent)
            
            #endif
            
            self.downloadURL = downloadURL
            self.normalizedDownloadURL = downloadURL.normalizedForInstallURL()
            self.assetURLs = try container.decodeIfPresent([String: URL].self, forKey: .assetURLs)
            
            self.size = try container.decode(Int64.self, forKey: .size)
            self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)?.lowercased()
            
            self._minOSVersion = try container.decodeIfPresent(String.self, forKey: .minOSVersion)
            
            #if !MARKETPLACE
            self._maxOSVersion = try container.decodeIfPresent(String.self, forKey: .maxOSVersion)
            #endif
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            
            throw error
        }
    }
}

public extension AppVersion
{
    var localizedVersion: String {
        if let marketingVersion
        {
            return marketingVersion
        }
        
        guard let buildVersion else { return self.version }
        
        let localizedVersion = "\(self.version) (\(buildVersion))"
        return localizedVersion
    }
    
    var versionID: String {
        // Use `nil` as fallback to prevent collisions between versions with builds and versions without.
        // 1.5 (4) -> "1.5|4"
        // 1.5.4 (no build) -> "1.5.4|nil"
        let buildVersion = self.buildVersion ?? "nil"
        
        let versionID = "\(self.version)|\(buildVersion)"
        return versionID
    }
}

public extension AppVersion
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppVersion>
    {
        return NSFetchRequest<AppVersion>(entityName: "AppVersion")
    }
    
    class func makeAppVersion(
        version: String,
        buildVersion: String?,
        date: Date,
        localizedDescription: String? = nil,
        downloadURL: URL,
        size: Int64,
        appBundleID: String,
        sourceID: String? = nil,
        in context: NSManagedObjectContext) -> AppVersion
    {
        let appVersion = AppVersion(context: context)
        appVersion.version = version
        appVersion.buildVersion = buildVersion
        appVersion.date = date
        appVersion.localizedDescription = localizedDescription
        appVersion.downloadURL = downloadURL
        appVersion.size = size
        appVersion.appBundleID = appBundleID
        appVersion.sourceID = sourceID

        return appVersion
    }
    
    var isSupported: Bool {
        if let minOSVersion = self.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion)
        {
            return false
        }
        else if let maxOSVersion = self.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion
        {
            return false
        }
        
        return true
    }
}
