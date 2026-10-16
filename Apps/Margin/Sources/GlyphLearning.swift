import CoreGraphics
import Handwriting
import InkCore
import Intelligence

/// The writer's own ink from one lasso, with what Vision read in it, handed to the glyph bank so it can learn
/// more samples of their characters. Stays on the device: nothing here is ever part of a request.
struct LearnableSelection {
    /// Only the strokes inside the lasso, and never generated ink.
    let strokes: [InkStroke]
    let reading: SelectionReading
    /// The page rectangle the reading's image covered.
    let cropBounds: CGRect

    /// Vision's per-character boxes (normalised to the crop, origin bottom-left) as page-space rectangles.
    var regions: [CharacterRegion] {
        guard cropBounds.width > 0, cropBounds.height > 0 else { return [] }
        return reading.characters.map { recognised in
            let box = recognised.box
            return CharacterRegion(
                character: recognised.character,
                box: CGRect(
                    x: cropBounds.minX + box.minX * cropBounds.width,
                    y: cropBounds.minY + (1 - box.maxY) * cropBounds.height,
                    width: box.width * cropBounds.width,
                    height: box.height * cropBounds.height))
        }
    }
}
