//
//  IV+HorizontalLayout.swift
//  Suwatte (iOS)
//
//  Created by Mantton on 2023-08-09.
//

import UIKit

protocol OffsetPreservingLayout: NSObject {
    var isInsertingCellsToTop: Bool { get set }
}

class HImageViewerLayout: UICollectionViewFlowLayout, OffsetPreservingLayout {
    var readingMode: ReadingMode!

    override init() {
        super.init()
        scrollDirection = .horizontal
        minimumLineSpacing = 0
        minimumInteritemSpacing = 0
        sectionInset = UIEdgeInsets.zero
        estimatedItemSize = .zero
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isInsertingCellsToTop: Bool = false {
        didSet {
            if isInsertingCellsToTop {
                contentSizeBeforeInsertingToTop = collectionViewContentSize
            }
        }
    }

    private var contentSizeBeforeInsertingToTop: CGSize?

    override func prepare() {
        if isInsertingCellsToTop {
            if let collectionView = collectionView, let oldContentSize = contentSizeBeforeInsertingToTop {
                UIView.performWithoutAnimation {
                    let newContentSize = self.collectionViewContentSize
                    let contentOffsetX = collectionView.contentOffset.x + (newContentSize.width - oldContentSize.width)
                    let contentOffsetY = collectionView.contentOffset.y + (newContentSize.height - oldContentSize.height)
                    let newOffset = CGPoint(x: contentOffsetX, y: contentOffsetY)
                    collectionView.contentOffset = newOffset
                }
            }
            contentSizeBeforeInsertingToTop = nil
            isInsertingCellsToTop = false
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let attributes = super.layoutAttributesForElements(in: rect) ?? []
        return attributes.map { base in

            var attribute = base
            if attribute.representedElementCategory == .cell {
                let indexPath = attribute.indexPath
                attribute = self.layoutAttributesForItem(at:indexPath) ?? base
            }
            
            return attribute
        }
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attribute = super.layoutAttributesForItem(at: indexPath)
        let isInverted = readingMode.isInverted
        attribute?.transform = isInverted ? .init(scaleX: -1, y: 1) : .identity
        return attribute
    }
}
