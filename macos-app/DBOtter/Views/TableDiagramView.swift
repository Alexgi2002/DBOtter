//
//  TableDiagramView.swift
//  DBOtter

import SwiftUI

struct TableDiagramView: View {
    let tableName: String
    let connectionId: UUID

    @State private var viewModel: TableDiagramViewModel
    @State private var canvasDrag: CGSize = .zero

    init(tableName: String, connectionId: UUID) {
        self.tableName = tableName
        self.connectionId = connectionId
        self._viewModel = State(initialValue: TableDiagramViewModel(connectionId: connectionId))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            canvasBackground

            if viewModel.isLoading {
                ProgressView("Cargando esquema...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error) { viewModel.refresh() }
            } else {
                diagramCanvas
            }

            diagramToolbar
        }
        .task { await viewModel.loadDiagram() }
    }

    // MARK: - Canvas background (pan gesture)

    private var canvasBackground: some View {
        Color(NSColor.windowBackgroundColor)
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        canvasDrag = value.translation
                    }
                    .onEnded { value in
                        viewModel.accumulatedPan = CGSize(
                            width: viewModel.accumulatedPan.width + value.translation.width,
                            height: viewModel.accumulatedPan.height + value.translation.height
                        )
                        canvasDrag = .zero
                    }
            )
    }

    // MARK: - Diagram canvas

    private var diagramCanvas: some View {
        let totalPan = CGSize(
            width: viewModel.accumulatedPan.width + canvasDrag.width,
            height: viewModel.accumulatedPan.height + canvasDrag.height
        )

        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Dot grid background
                Canvas { context, size in
                    let spacing: CGFloat = 24
                    let dotSize: CGFloat = 1.5
                    let offsetX = totalPan.width.truncatingRemainder(dividingBy: spacing)
                    let offsetY = totalPan.height.truncatingRemainder(dividingBy: spacing)

                    var x = offsetX
                    while x < size.width {
                        var y = offsetY
                        while y < size.height {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)),
                                with: .color(Color.primary.opacity(0.08))
                            )
                            y += spacing
                        }
                        x += spacing
                    }
                }
                .allowsHitTesting(false)

                // FK connection lines (below nodes)
                Canvas { context, size in
                    drawConnections(context: context, pan: totalPan)
                }
                .allowsHitTesting(false)

                // Nodes
                ForEach(viewModel.tableNames, id: \.self) { name in
                    if let structure = viewModel.tableStructures[name],
                       let position = viewModel.nodePositions[name] {
                        NodeWrapper(
                            structure: structure,
                            position: position,
                            isSelected: viewModel.selectedTable == name,
                            zoom: viewModel.zoom,
                            pan: totalPan,
                            onTap: { viewModel.selectTable(name) },
                            onDragChanged: { delta in
                                viewModel.nodeDragDeltas[name] = delta
                            },
                            onPositionChanged: { newPos in
                                viewModel.nodePositions[name] = newPos
                                viewModel.nodeDragDeltas[name] = nil
                            }
                        )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    viewModel.applyZoom(value.magnification)
                }
                .onEnded { _ in
                    viewModel.resetMagnification()
                }
        )
        .overlay(alignment: .bottomTrailing) {
            // Zoom controls
            HStack(spacing: 2) {
                Button(action: { viewModel.zoomOut() }) {
                    Image(systemName: "minus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Alejar")

                Text("\(Int(viewModel.zoom * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 40)

                Button(action: { viewModel.zoomIn() }) {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Acercar")

                Divider().frame(height: 16)

                Button(action: {
                    viewModel.resetZoom()
                    canvasDrag = .zero
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Restablecer vista")

                Button(action: { viewModel.autoLayout() }) {
                    Image(systemName: "square.grid.3x3.middle.filled").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Auto Layout")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .padding(.bottom, 16)
            .padding(.trailing, 16)
        }
    }

    // MARK: - Toolbar

    private var diagramToolbar: some View {
        VStack(spacing: 0) {
            // Stats bar
            HStack(spacing: 12) {
                Label("\(viewModel.tableNames.count) tablas", systemImage: "tablecells")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("\(viewModel.connections.count) relaciones", systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Recargar diagrama")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
    // MARK: - FK Connection drawing

    private func drawConnections(context: GraphicsContext, pan: CGSize) {
        for conn in viewModel.connections {
            guard
                let fromStructure = viewModel.tableStructures[conn.fromTable],
                let toStructure   = viewModel.tableStructures[conn.toTable]
            else { continue }

            // Find row indices
            let fromIdx = fromStructure.columns.firstIndex { $0.name == conn.fromColumn } ?? 0
            let toIdx   = toStructure.columns.firstIndex   { $0.name == conn.toColumn   } ?? 0

            let from = viewModel.anchorPoint(table: conn.fromTable, columnIndex: fromIdx, side: .right, pan: pan)
            let to   = viewModel.anchorPoint(table: conn.toTable,   columnIndex: toIdx,   side: .left,  pan: pan)

            // Determine direction for bezier handles
            let dx = abs(to.x - from.x)
            let cpOffset = max(dx * 0.5, 60)
            let cp1 = CGPoint(x: from.x + cpOffset, y: from.y)
            let cp2 = CGPoint(x: to.x   - cpOffset, y: to.y)

            var path = Path()
            path.move(to: from)
            path.addCurve(to: to, control1: cp1, control2: cp2)

            let isHighlighted = viewModel.selectedTable == conn.fromTable || viewModel.selectedTable == conn.toTable
            let lineColor = isHighlighted ? Color.accentColor : Color.blue.opacity(0.45)
            let lineWidth = isHighlighted ? 2.0 : 1.2

            context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Arrowhead at destination
            let arrowSize: CGFloat = 7
            let angle = atan2(to.y - cp2.y, to.x - cp2.x)
            var arrow = Path()
            arrow.move(to: to)
            arrow.addLine(to: CGPoint(
                x: to.x - arrowSize * cos(angle - .pi / 7),
                y: to.y - arrowSize * sin(angle - .pi / 7)
            ))
            arrow.addLine(to: CGPoint(
                x: to.x - arrowSize * cos(angle + .pi / 7),
                y: to.y - arrowSize * sin(angle + .pi / 7)
            ))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(lineColor))

            // Dot at origin
            context.fill(
                Path(ellipseIn: CGRect(x: from.x - 3, y: from.y - 3, width: 6, height: 6)),
                with: .color(lineColor)
            )
        }
    }
}

// MARK: - Node Wrapper (handles position + drag within canvas)

private struct NodeWrapper: View {
    let structure: TableStructure
    let position: CGPoint
    let isSelected: Bool
    let zoom: CGFloat
    let pan: CGSize
    let onTap: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onPositionChanged: (CGPoint) -> Void

    @State private var dragDelta: CGSize = .zero

    private var screenX: CGFloat { position.x * zoom + pan.width + dragDelta.width }
    private var screenY: CGFloat { position.y * zoom + pan.height + dragDelta.height }

    var body: some View {
        TableNodeView(
            structure: structure,
            isSelected: isSelected,
            onDrag: { delta in
                dragDelta = delta
                onDragChanged(delta)
            },
            onTap: onTap,
            onDragEnded: { _ in
                let newPos = CGPoint(
                    x: position.x + dragDelta.width / zoom,
                    y: position.y + dragDelta.height / zoom
                )
                onPositionChanged(newPos)
                dragDelta = .zero
            }
        )
        .scaleEffect(zoom)
        .position(x: screenX, y: screenY)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.9), value: dragDelta == .zero)
    }
}

#Preview {
    TableDiagramView(tableName: "users", connectionId: UUID())
        .frame(width: 900, height: 650)
}
