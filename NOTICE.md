# Attribution and provenance

This native SwiftUI implementation was extracted from the `ios/` work in [Cxsmxnaut/grademaxxing](https://github.com/Cxsmxnaut/grademaxxing) on October 11, 2026. The web checkout's base revision was `3f7d4b9f8cf5b19f3853fee55e6efbde60a47ac7`; native sources were newly written, uncommitted work at extraction.

Grademaxxing is an AGPLv3-derived modification of GradeCompass. This repository preserves that license in `LICENSE.txt`. The upstream repository retains the web application's history and attribution. Native ports follow its StudentVUE wire contracts, grade/GPA policies, and synthetic calculation fixtures. The TypeScript generators intentionally use the upstream implementations as their reference.

Changes in this repository: SwiftUI screens and state; Swift API/session, contract, calculation, cache, and preview implementations; synthetic native checks; an Xcode project and demo UI tests; native setup and validation documentation. This repository does not contain a copy of the web application's deployment or backend.

Grademaxxing is independent of Edupoint, school districts, and schools. StudentVUE is a trademark of Edupoint Educational Systems LLC.
