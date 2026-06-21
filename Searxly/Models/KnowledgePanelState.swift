//
//  KnowledgePanelState.swift
//  Searxly
//
//  Models for the SERP right-column knowledge panel (Grokipedia-only).
//

import Foundation

enum KnowledgePanelDisplayState: Equatable {
    case hidden
    case loading(query: String)
    case ready(KnowledgePanelContent)
}

struct KnowledgePanelContent: Equatable {
    let query: String
    let kind: KnowledgePanelKind
}

enum KnowledgePanelKind: Equatable {
    case entity(EntityPanelData)
}

struct EntityPanelData: Equatable {
    let title: String
    let aboutParagraphs: [String]
    let entityKind: OfficialEntityDatabase.EntityKind?
    let officialSiteURL: String?
    let officialSiteLabel: String?
    let grokipediaURL: String?
    let grokipediaBannerURL: URL?
    let facts: [KnowledgeFact]
}

struct KnowledgeFact: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
}