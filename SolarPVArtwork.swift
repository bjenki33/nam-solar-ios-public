import SwiftUI

struct SolarPVArtwork: View {
    let scale: CGFloat
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("solar-pv", bundle: .main).renderingMode(.original).resizable().scaledToFit()
                .frame(width: 88 * scale, height: 40 * scale).offset(y: 8 * scale)
            Image("solar-sun", bundle: .main).renderingMode(.original).resizable().scaledToFit()
                .frame(width: 72 * scale, height: 48 * scale).offset(x: 32 * scale)
                .allowsHitTesting(false)
        }.frame(width: 104 * scale, height: 48 * scale).accessibilityHidden(true)
    }
}
