//
//  MetaEndpointPayload.swift
//  LucidCodeGen
//
//  Created by Théophane Rupin on 3/29/19.
//

import Meta

struct MetaEndpointPayload {
    
    let endpointName: String
    
    let descriptions: Descriptions
    
    func meta() throws -> [FileBodyMember] {
        return [
            [
                Comment.mark("Endpoint Payload"),
                EmptyLine(),
                try endpointPayload(),
                EmptyLine(),
                Comment.mark("Decodable"),
                EmptyLine(),
                try decodableExtension()
            ],
            try metadata().flatMap {
                [
                    EmptyLine(),
                    Comment.mark("Metadata"),
                    EmptyLine(),
                    $0
                ]
            } ?? [], [
                EmptyLine(),
                Comment.mark("Accessors"),
                EmptyLine(),
                try accessors()
            ]
        ].flatMap { member -> [FileBodyMember] in member }
    }
    
    private func endpointPayload() throws -> Type {
        let endpoint = try descriptions.endpoint(for: endpointName)

        return Type(identifier: endpoint.typeID)
            .with(kind: .struct)
            .with(accessLevel: .public)
            .adding(member: EmptyLine())
            .adding(member: Property(variable: endpoint.payloadVariable.with(type: try payloadPropertyTypeID())))
            .adding(member: EmptyLine())
            .adding(member: Property(variable: endpoint.metadataVariable.with(type: try metadataPropertyTypeID())))
            .adding(member: EmptyLine())
            .adding(member: try entityMetadataComputedProperty())
    }
    
    private func payloadPropertyTypeID() throws -> TypeIdentifier {
        let endpoint = try descriptions.endpoint(for: endpointName)
        return endpoint.payloadTypeID
    }
    
    private func metadataPropertyTypeID() throws -> TypeIdentifier {
        let endpoint = try descriptions.endpoint(for: endpointName)
        return endpoint.metadataTypeID
    }

    private func entityMetadataComputedProperty() throws -> ComputedProperty {
        let endpoint = try descriptions.endpoint(for: endpointName)
        let rootEntity = try descriptions.entity(for: endpoint.entity.entityName)

        let returnReference: Reference
        if endpoint.payloadTypeID.isArray == false {
            returnReference = .array(with: [
                endpoint.payloadVariable.reference | (endpoint.payloadTypeID.isOptional ? .unwrap : .none) + .named("entityMetadata")
            ]) + .named("lazy") + .named(.map) | .block(FunctionBody()
                .adding(member: Reference.named("$0"))
            ) + .named("any")
        } else {
            returnReference = endpoint.payloadVariable.reference |
                (endpoint.payloadTypeID.isOptional ? .unwrap : .none) +
                .named("lazy") + .named(.map) | .block(FunctionBody()
                    .adding(member: .named("$0") + .named("entityMetadata"))
                ) + .named("any")
        }
        
        return ComputedProperty(variable: Variable(name: "entityMetadata")
            .with(type: .anySequence(element: .optional(wrapped: try rootEntity.metadataTypeID(descriptions)))))
            .adding(member: Return(value: returnReference))
    }
    
    private func decodableExtension() throws -> Extension {
        let endpoint = try descriptions.endpoint(for: endpointName)

        let keys = try decodableKeys()
        let subkeys = try decodableSubkeys()
        
        return Extension(type: endpoint.typeID)
            .adding(inheritedType: .decodable)
            .adding(member: EmptyLine())
            .adding(member: keys)
            .adding(member: keys != nil ? EmptyLine() : nil)
            .adding(member: subkeys)
            .adding(member: subkeys != nil ? EmptyLine() : nil)
            .adding(member: try initFromDecoder())
    }
    
    private func decodableKeys() throws -> Type? {
        let endpoint = try descriptions.endpoint(for: endpointName)

        switch try endpoint.initializerType() {
        case .initFromKey(let key),
             .initFromSubkey(let key, _),
             .mapFromSubstruct(let key, _):
            return Type(identifier: TypeIdentifier(name: "Keys"))
                .with(kind: .enum(indirect: false))
                .with(accessLevel: .private)
                .adding(inheritedType: .string)
                .adding(inheritedType: .codingKey)
                .adding(member: Case(name: key))
            
        case .initFromRoot:
            return nil
        }
    }
    
    private func decodableSubkeys() throws -> Type? {
        let endpoint = try descriptions.endpoint(for: endpointName)

        switch try endpoint.initializerType() {
        case .initFromSubkey(_ , let subkey):
            return Type(identifier: TypeIdentifier(name: "Subkeys"))
                .with(kind: .enum(indirect: false))
                .with(accessLevel: .private)
                .adding(inheritedType: .string)
                .adding(inheritedType: .codingKey)
                .adding(member: Case(name: subkey.camelCased().variableCased))
            
        case .mapFromSubstruct(_, let subkey):
            return Type(identifier: TypeIdentifier(name: "NestedValue"))
                .with(kind: .struct)
                .with(accessLevel: .private)
                .adding(inheritedType: .decodable)
                .adding(member: Property(variable: Variable(name: subkey.camelCased().variableCased)
                    .with(type: endpoint.payloadTypeID.arrayElementOrSelf.wrappedOrSelf)
                ))
            
        case .initFromKey,
             .initFromRoot:
            return nil
        }
    }
    
    private func initFromDecoder() throws -> Function {
        let endpoint = try descriptions.endpoint(for: endpointName)

        var function = Function.initFromDecoder.with(accessLevel: .public)
        let decodeMethod: Reference = endpoint.entity.optional ? .named("decodeIfPresent") : .named("decode")
        
        let container = Assignment(
            variable: Variable(name: "container"),
            value: Reference.named("decoder").container(keyedBy: TypeIdentifier(name: "Keys"))
        )

        var payloadPropertyTypeID = try self.payloadPropertyTypeID().wrappedOrSelf
        if let arrayElementTypeID = payloadPropertyTypeID.arrayElement {
            payloadPropertyTypeID = .array(element: .failableValue(of: arrayElementTypeID))
        }
        
        let metadataKey: String?
        switch try endpoint.initializerType() {
        case .initFromRoot:
            metadataKey = nil
            function = function.adding(member: Assignment(
                variable: Reference.named(.`self`) + endpoint.payloadVariable.reference,
                value: .try | payloadPropertyTypeID.reference | .call(Tuple()
                    .adding(parameter: TupleParameter(name: "from", value: Reference.named("decoder")))
                )
            ))
        case .initFromKey(let key):
            metadataKey = key
            function = function
                .adding(member: container)
                .adding(member: Assignment(
                    variable: .named(.`self`) + endpoint.payloadVariable.reference,
                    value: .try | .named("container") + decodeMethod | .call(Tuple()
                        .adding(parameter: TupleParameter(value: payloadPropertyTypeID.reference + .named(.`self`)))
                        .adding(parameter: TupleParameter(name: "forKey", value: +.named(key)))
                    ) | (
                        payloadPropertyTypeID.isArray ?
                            +.named("lazy") + .named(.compactMap) | .block(FunctionBody()
                                .adding(member: .named("$0") + .named("value") | .call())
                            ) + .named("any") : .none
                    )
                ))
        case .initFromSubkey(let key, let subkey):
            metadataKey = key
            function = function
                .adding(member: container)
                .adding(member: Assignment(
                    variable: Variable(name: "nestedContainer"),
                    value: .try | .named("container") + .named("nestedContainer") | .call(Tuple()
                        .adding(parameter: TupleParameter(name: "keyedBy", value: .named("Subkeys") + .named(.`self`)))
                        .adding(parameter: TupleParameter(name: "forKey", value: +.named(key)))
                    )
                ))
                .adding(member: Assignment(
                    variable: .named(.`self`) + endpoint.payloadVariable.reference,
                    value: .try | .named("nestedContainer") + decodeMethod | .call(Tuple()
                        .adding(parameter: TupleParameter(value: payloadPropertyTypeID.reference + .named(.`self`)))
                        .adding(parameter: TupleParameter(name: "forKey", value: +.named(subkey.camelCased().variableCased)))
                    ) | (
                        payloadPropertyTypeID.isArray ?
                            +.named("lazy") + .named(.compactMap) | .block(FunctionBody()
                                .adding(member: .named("$0") + .named("value") | .call())
                            ) + .named("any") : .none
                    )
                ))
        case .mapFromSubstruct(let key, let subkey):
            metadataKey = key
            var nestedDecodingType = TypeIdentifier(name: "NestedValue")
            if endpoint.entity.structure.isArray {
                nestedDecodingType = .array(element: .failableValue(of: nestedDecodingType))
            }
            function = function
                .adding(member: container)
                .adding(member: Assignment(
                    variable: .named(.`self`) + endpoint.payloadVariable.reference,
                    value: .try | .named("container") + decodeMethod | .call(Tuple()
                        .adding(parameter: TupleParameter(value: nestedDecodingType.reference + .named(.`self`)))
                        .adding(parameter: TupleParameter(name: "forKey", value: +.named(key)))
                    ) + .named("lazy") + .named(endpoint.entity.structure.isArray ? .compactMap : .map) | .block(FunctionBody()
                        .adding(member: Reference.named("$0") | (+.named("value") | .call() | .unwrap) + .named(subkey.camelCased().variableCased))
                    ) + .named("any")
                ))
        }
        
        if endpoint.metadata == nil {
            return function.adding(member: Assignment(
                variable: .named(.`self`) + .named("endpointMetadata"),
                value: TypeIdentifier.voidMetadata.reference | .call()
            ))
        } else if let metadataKeyName = metadataKey {
            return function.adding(member: Assignment(
                variable: .named(.`self`) + .named("endpointMetadata"),
                value: try .try | .named("container") + decodeMethod | .call(Tuple()
                    .adding(parameter: TupleParameter(value: metadataPropertyTypeID().reference + .named(.`self`)))
                    .adding(parameter: TupleParameter(name: "forKey", value: +.named(metadataKeyName)))
                )
            ))
        } else {
            throw CodeGenError.unsupportedMetadataIdentifier
        }
    }
    
    private func metadata() throws -> Type? {
        let endpoint = try descriptions.endpoint(for: endpointName)
        guard let metadata = endpoint.metadata else { return nil }
        
        return Type(identifier: endpoint.metadataTypeID)
            .with(kind: .struct)
            .with(accessLevel: .public)
            .adding(inheritedType: .decodable)
            .adding(inheritedType: .endpointMetadata)
            .adding(members: metadata.map {
                return Property(variable: $0.variable.with(type: $0.typeID))
                    .with(accessLevel: .public)
            })
    }
    
    private func accessors() throws -> Extension {
        let endpoint = try descriptions.endpoint(for: endpointName)
        let entity = try descriptions.entity(for: endpoint.entity.entityName)
        let extractableEntities = try entity.extractablePropertyEntities(descriptions)
        
        var body = try extractableEntities.flatMap { entity -> [TypeBodyMember] in
            return [
                EmptyLine(),
                try accessor(for: entity, isExtractable: true)
            ]
        }
        
        if extractableEntities.contains(where: { $0.name == entity.name }) == false {
            body.append(EmptyLine())
            body.append(try accessor(for: entity, isExtractable: false))
        }
        
        return Extension(type: endpoint.typeID).with(body: body)
    }
    
    private func accessor(for entity: Entity, isExtractable: Bool) throws -> ComputedProperty {
        let endpoint = try descriptions.endpoint(for: endpointName)
        
        let selfMapping: Reference? = entity.name == endpoint.entity.entityName ?
            endpoint.payloadVariable.reference | (endpoint.entity.structure.isArray == false ? +.named("values") | .call() : .none) + .named("lazy") + .named(.map) | .block(FunctionBody()
                .adding(member: entity.typeID().reference | .call(Tuple()
                    .adding(parameter: TupleParameter(name: "payload", value: .named("$0") + .named("rootPayload")))
                ))
            ) + .named("any") : nil
        
        let extractionMapping: Reference? = isExtractable ?
            endpoint.payloadVariable.reference | (endpoint.entity.structure.isArray == false ? +.named("values") | .call() : .none) + .named("lazy") + .named(.flatMap) | .block(FunctionBody()
                .adding(member: .named("$0") + .named("rootPayload") + entity.payloadEntityAccessorVariable.reference)
            ) + .named("any") : nil
        
        let mappingReferences = [selfMapping, extractionMapping].compactMap { $0 }

        return ComputedProperty(variable: entity.payloadEntityAccessorVariable
            .with(type: .anySequence(element: entity.typeID())))
            .adding(member: Return(value: (mappingReferences.isEmpty == false ?
                .array(with: mappingReferences) + .named("joined") | .call() :
                .array()) + .named("any")
            ))
    }
}
