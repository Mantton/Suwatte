//
//  CPVM+ActionState.swift
//  Suwatte (iOS)
//
//  Created by Mantton on 2023-08-23.
//

import Foundation

private typealias ViewModel = ProfileView.ViewModel

extension ViewModel {
    func setActionState(_ safetyCheck: Bool = false) async {
        let state = await calculateActionState(safetyCheck)
        await animate { [weak self] in
            self?.actionState = state
        }
    }

    func calculateActionState(_ safetyCheck: Bool) async -> ActionState {
        guard !chapters.isEmpty else {
            return .init(state: .none)
        }

        let actor = await RealmActor.shared()

        let marker = await actor
            .getContentMarker(for: identifier)
        
        _ = STTHelpers.getReadingMode(for: identifier) // To Update Reading Mode

        guard let marker else {
            // No Progress marker present, return first chapter
            let chapter = chapters.last!
            return .init(state: .start,
                         chapter: chapter,
                         marker: nil)
        }
        
        // This Method gets called twice. First After Chapters are loaded & after syncing is complete
        // It should return the current action state if the max read chapter was not changed after syncing
        if safetyCheck, let currentRead = actionState.chapter?.chapterOrderKey,
           let maxRead =  marker.maxReadChapterKey, maxRead <= currentRead {
            return actionState
        }

        guard let chapterRef = marker.currentChapter else {
            // Marker Exists but there is not reference to the chapter
            let maxReadChapterKey = marker.maxReadChapterKey

            // Check the max read chapter and use this instead
            guard let maxReadChapterKey else {
                // No Maximum Read Chapter, meaning marker exists without any reference or read chapers, point to first chapter instead
                let chapter = chapters.last!
                return .init(state: .start,
                             chapter: chapter,
                             marker: nil)
            }

            // Get The latest chapter
            guard let targetIndex = chapters.lastIndex(where: { $0.chapterOrderKey >= maxReadChapterKey }) else {
                let target = chapters.first!

                return .init(state: .reRead,
                             chapter: target)
            }
            // We currently have the index of the last read chapter, if this index points to the last chapter, represent a reread else get the next up
            guard let currentMaxReadChapter = chapters.get(index: targetIndex) else {
                return .init(state: .none) // Should Never Happen
            }

            if currentMaxReadChapter == chapters.first { // Max Read is lastest available chapter
                return .init(state: .reRead, chapter: currentMaxReadChapter)
            } else if let nextUpChapter = chapters.get(index: max(0, targetIndex - 1)) { // Point to next after max read
                return .init(state: .upNext,
                             chapter: nextUpChapter)
            }

            return .init(state: .none)
        }

        // Fix Situation where the chapter being referenced is not in the joined chapter list by picking the last where the numbers match
        var correctedChapterId = chapterRef.id
        if !chapters.contains(where: { $0.id == chapterRef.id }),
           let chapter = chapters.last(where: { $0.number >= chapterRef.number })
        {
            correctedChapterId = chapter.id
        }

        let chapter = chapters
            .first(where: { $0.id == correctedChapterId })

        guard let chapter else {
            return .init(state: .start, chapter: chapters.last!)
        }

        if !marker.isCompleted {
            // Marker Exists, Chapter has not been completed, resume
            return .init(state: .resume,
                         chapter: chapter,
                         marker: .init(progress: marker.progress ?? 0.0,
                                       date: marker.dateRead))
        }
        // Chapter has been completed, Get Current Index
        guard var index = chapters.firstIndex(where: { $0.id == correctedChapterId }) else {
            return .init(state: .start, chapter: chapters.last!) // Should never occur due to earlier correction
        }

        // Current Index is equal to that of the last available chapter
        // Set action state to re-read
        // marker is nil to avoid progress display
        if index == 0 {
            if content.status == .COMPLETED, let chapter = chapters.last {
                return .init(state: .restart,
                             chapter: chapter, marker: nil)
            }
            return .init(state: .reRead, chapter: chapter, marker: nil)
        }

        // index not 0, decrement, sourceIndex moves inverted
        index -= 1
        let next = chapters.get(index: index)
        return .init(state: .upNext,
                     chapter: next,
                     marker: nil)
    }
}
