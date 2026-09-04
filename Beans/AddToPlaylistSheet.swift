import SwiftUI

struct AddToPlaylistSheet: View {
    let song: Song

    var body: some View {
        AddToLocalPlaylistSheet(song: song)
    }
}
