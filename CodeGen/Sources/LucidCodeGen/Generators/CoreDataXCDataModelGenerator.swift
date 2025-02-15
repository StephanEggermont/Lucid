//
//  CoreDataXCDataModelGenerator.swift
//  LucidCodeGen
//
//  Created by Théophane Rupin on 4/18/19.
//

import Meta
import PathKit
import LucidCodeGenCore

public final class CoreDataXCDataModelGenerator: Generator {

    public lazy var outputDirectory = OutputDirectory.coreDataModel(version: parameters.appVersion)

    public var targetName = TargetName.app

    public let name = "Core Data model"
    
    private let filename = "contents"

    private let parameters: GeneratorParameters

    public init(_ parameters: GeneratorParameters) {
        self.parameters = parameters
    }
    
    public func generate(for element: Description, in directory: Path, organizationName: String) throws -> SwiftFile? {
        guard parameters.shouldGenerateDataModel else { return nil }

        guard let currentDescriptions = parameters.descriptions[parameters.appVersion] else {
            fatalError("Could not find descriptions for version: \(parameters.appVersion.dotDescription)")
        }
        
        guard element == .all else { return nil }
        
        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="14460.32" systemVersion="18A391" minimumToolsVersion="Automatic" sourceLanguage="Swift" userDefinedModelVersionIdentifier="\(parameters.appVersion.dotDescription)">

        \(try currentDescriptions.entities.filter { $0.persist }.flatMap { entity -> [String] in
            return try entity.versionHistory.resolve(
                for: entity,
                in: parameters.descriptions,
                currentVersion: parameters.appVersion,
                historyVersions: parameters.historyVersions
            ).map {
                try generate(for: $0, in: $1, version: $2, previousName: $3, previousDescriptions: $4)
            }
        }.joined(separator: "\n"))
        
        </model>
        """
        
        return SwiftFile(content: content, path: directory + filename)
    }
    
    private func generate(for entityName: String, in currentDescriptions: Descriptions, version: Version, previousName: String?, previousDescriptions: Descriptions?) throws -> String {

        let entity = try currentDescriptions.entity(for: entityName)

        let versionHash: String = {
            var previousEntity: Entity? = nil
            var currentHash: String = String()
            (parameters.historyVersions.reversed() + [version]).forEach { version in
                let entity = try? parameters.descriptions[version]?.entity(for: entityName)
                if entity?.identifier.identifierType != previousEntity?.identifier.identifierType {
                    currentHash = version.dotDescription
                }
                previousEntity = entity
            }
            return currentHash
        }()

        let elementIDText: String

        if let legacyPreviousName = entity.legacyPreviousName {
            elementIDText = " elementID=\"\(legacyPreviousName)\""
        } else if let previousName = previousName, previousName != entityName {
            guard let previousDescriptions = previousDescriptions else {
                fatalError("Could not find descriptions for previous version, but found previous name \(previousName).")
            }
            let previousEntity = try previousDescriptions.entity(for: previousName)
            let previousEntityCoreDataName = previousEntity.coreDataName(for: previousDescriptions.version, useCoreDataLegacyNaming: parameters.useCoreDataLegacyNaming)
            elementIDText = " elementID=\"\(previousEntityCoreDataName)\""
        } else {
            elementIDText = String()
        }
        let entityCoreDataName = entity.coreDataName(for: version, useCoreDataLegacyNaming: parameters.useCoreDataLegacyNaming)
        let entityCoreDataManagedName = try entity.coreDataEntityTypeID(for: version).swiftString

        return """
            <entity name="\(entityCoreDataName)" representedClassName="\(entityCoreDataManagedName)" syncable="YES" codeGenerationType="class"\(elementIDText)>
                <attribute name="_identifier" attributeType="\(try identifierCoreDataType(for: entity, in: currentDescriptions))" usesScalarValueType="YES" syncable="YES" optional="YES" versionHashModifier="\(versionHash)"/>
                <attribute name="__identifier" attributeType="\(entity.hasVoidIdentifier ? "Integer 64" : "String")" usesScalarValueType="YES" syncable="YES" optional="YES" versionHashModifier="\(versionHash)"/>
                <attribute name="\(parameters.useCoreDataLegacyNaming ? "__typeUID" : "__type_uid")" attributeType="String" usesScalarValueType="YES" syncable="YES" optional="YES"/>
                <fetchIndex name="remoteIdentifier">
                    <fetchIndexElement property="_identifier" type="Binary" order="ascending"/>
                </fetchIndex>
                <fetchIndex name="localIdentifier">
                    <fetchIndexElement property="__identifier" type="Binary" order="ascending"/>
                </fetchIndex>

        \(entity.remote ?
            """
                    <attribute name="\(parameters.useCoreDataLegacyNaming ? "_remoteSynchronizationState" : "_remote_synchronization_state")" attributeType="String" syncable="YES" optional="YES"/>
            """
            : String()
        )
        \(try (entity.usedProperties + entity.systemProperties.map { $0.property }).map { property in
            let propertyCoreDataName = property.coreDataName(useCoreDataLegacyNaming: parameters.useCoreDataLegacyNaming)
            let propertyElementIDText = property.previousName.flatMap { " elementID=\"_\($0)\"" } ?? ""
            var value = String()
            if property.isRelationship && property.isArray == false {
                let _propertyElementIDText = property.previousName.flatMap { " elementID=\"__\($0)\"" } ?? ""
                let _typeUIDElementIDText = property.previousName.flatMap { " elementID=\"__\($0)\(parameters.useCoreDataLegacyNaming ? "TypeUID" : "_type_uid")\"" } ?? ""

                value += """
                        <attribute name="_\(propertyCoreDataName)" optional="YES" attributeType="\(try propertyCoreDataType(for: property, in: currentDescriptions))" syncable="YES"\(propertyElementIDText)/>
                        <attribute name="__\(propertyCoreDataName)" optional="YES" attributeType="String" syncable="YES"\(_propertyElementIDText)/>
                        <attribute name="__\(propertyCoreDataName)\(parameters.useCoreDataLegacyNaming ? "TypeUID" : "_type_uid")" optional="YES" attributeType="String" syncable="YES"\(_typeUIDElementIDText)/>
                """
            } else {
                let optional = property.nullable || property.lazy
                let optionalText = optional ? " optional=\"YES\"" : ""
                let defaultValueText = property.defaultValue.flatMap { " \($0.coreDataAttributeName)=\"\($0.coreDataValue)\"" } ?? ""

                value += """
                        <attribute name="_\(propertyCoreDataName)"\(optionalText) attributeType="\(try propertyCoreDataType(for: property, in: currentDescriptions))" \(property.propertyType.usesScalarValueType ? "usesScalarValueType=\"YES\" ": "")syncable="YES"\(propertyElementIDText)\(defaultValueText)/>
                """
            }
            if property.lazy {
                value += """
                
                        <attribute name="__\(propertyCoreDataName)\(parameters.useCoreDataLegacyNaming ? "ExtraFlag" : "_lazy_flag")" optional="NO" attributeType="\(PropertyScalarType.bool.coreDataType)" usesScalarValueType="YES" syncable="YES" defaultValueString="0"/>
                """
            }
            return value
        }.joined(separator: "\n"))
            </entity>
        """
    }
    
    private func identifierCoreDataType(for entity: Entity, in descriptions: Descriptions) throws -> String {
        switch entity.identifier.identifierType {
        case .property(let name):
            let property = try entity.property(for: name)
            switch property.propertyType {
            case .scalar(let scalarType):
                return scalarType.coreDataType
            case .relationship(let relationship):
                let relationshipEntity = try descriptions.entity(for: relationship.entityName)
                return try identifierCoreDataType(for: relationshipEntity, in: descriptions)
            case .array,
                 .subtype:
                throw CodeGenError.cannotPersistIdentifier(entity.name)
            }
            
        case .relationships(let type, _),
             .scalarType(let type):
            return type.coreDataType

        case .void:
            return PropertyScalarType.int.coreDataType
        }
    }
    
    private func propertyCoreDataType(for property: EntityProperty, in descriptions: Descriptions) throws -> String {
        switch property.propertyType {
        case .subtype(let name):
            let subtype = try descriptions.subtype(for: name)
            return subtype.coreDataType
        case .relationship(let relationship):
            switch relationship.association {
            case .toMany:
                return "Binary"
            case .toOne:
                let relationshipEntity = try descriptions.entity(for: relationship.entityName)
                return try identifierCoreDataType(for: relationshipEntity, in: descriptions)
            }
        case .scalar(let type):
            return type.coreDataType
        case .array:
            return "Binary"
        }
    }
}

private extension PropertyScalarType {
    
    var coreDataType: String {
        switch self {
        case .string,
             .url,
             .color:
            return "String"
        case .int,
             .bool:
            return "Integer 64"
        case .double,
             .seconds,
             .milliseconds:
            return "Double"
        case .float:
            return "Float"
        case .date:
            return "Date"
        }
    }
}

private extension Subtype {
    
    var coreDataType: String {
        switch items {
        case .cases:
            return "String"
        case .options:
            return "Integer 64"
        case .properties:
            return "Binary"
        }
    }
}

private extension DefaultValue {
    
    var coreDataAttributeName: String {
        switch self {
        case .bool,
             .float,
             .int,
             .string,
             .enumCase,
             .`nil`,
             .seconds,
             .milliseconds:
            return "defaultValueString"
        case .date,
             .currentDate:
            return "defaultDateTimeInterval"
        }
    }

    var coreDataValue: String {
        switch self {
        case .bool(let value):
            return value ? "1" : "0"
        case .float(let value):
            return value.description
        case .int(let value):
            return value.description
        case .string(let value):
            return value
        case .date(let date):
            return date.timeIntervalSince1970.description
        case .currentDate:
            return "0"
        case .enumCase(let value):
            return value
        case .`nil`:
            return "nil"
        case .seconds(let value):
            return value.description
        case .milliseconds(let value):
            return (value / 1000).description
        }
    }
}

private extension Array where Element == VersionHistoryItem {
    
    typealias ResolvedModelMapping = (
        entityName: String,
        descriptions: Descriptions,
        version: Version,
        previousName: String?,
        previousDescriptions: Descriptions?
    )
    
    func resolve(for entity: Entity, in descriptions: [Version: Descriptions], currentVersion: Version, historyVersions: [Version]) throws -> [ResolvedModelMapping] {

        guard let addedAtVersion = entity.addedAtVersion else {
            fatalError("Could not find added_at_version for entity: \(entity.name)")
        }

        var mappings = [ResolvedModelMapping]()

        for (index, version) in map({ $0.version }).enumerated() {

            let isLatestVersion = index == count - 1
            let descriptionsVersion: Version
            if isLatestVersion {
                descriptionsVersion = currentVersion
            } else {
                let nextItem = self[index+1]
                if nextItem.previousName != nil {
                    // we are migrating this version to the new name, so we must remove the previous version from the model
                    continue
                }
                descriptionsVersion = historyVersions.first { $0 < nextItem.version || Version.isMatchingRelease($0, version) } ?? addedAtVersion
            }

            guard let versionDescriptions = descriptions[descriptionsVersion] else {
                fatalError("Could not find descriptions for version: \(descriptionsVersion)")
            }

            let versionedName = entity.nameForVersion(descriptionsVersion)
            let versionedPreviousName = entity.previousNameForCoreData
            let versionedPreviousDescriptions: Descriptions?

            if let versionedPreviousName = versionedPreviousName {
                guard let renamedHistoryIndex = firstIndex(where: { $0.previousName == versionedPreviousName }) else {
                    fatalError("Could not find index of previous name \(versionedPreviousName) in entity \(entity.name).")
                }
                guard renamedHistoryIndex > 0 else {
                    fatalError("First version of entity \(entity.name) should not have previous_name.")
                }
                let previousHistoryItem = self[renamedHistoryIndex-1]
                versionedPreviousDescriptions = descriptions[previousHistoryItem.version]
            } else {
                versionedPreviousDescriptions = nil
            }

            mappings.append((
                entityName: versionedName,
                descriptions: versionDescriptions,
                version: version,
                previousName: versionedPreviousName,
                previousDescriptions: versionedPreviousDescriptions
            ))
        }

        return mappings
    }
}
