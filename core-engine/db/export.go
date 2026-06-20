package db

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/xuri/excelize/v2"
)

// ExportManager maneja exportaciones profesionales
type ExportManager struct {
	client DatabaseClient
}

// NewExportManager crea un nuevo export manager
func NewExportManager(client DatabaseClient) *ExportManager {
	return &ExportManager{client: client}
}

// Export ejecuta la exportación según las opciones
func (em *ExportManager) Export(ctx context.Context, w io.Writer, opts ExportOptions) (*ExportResult, error) {
	// Validar formato
	validFormats := map[string]bool{
		"csv": true, "xlsx": true, "json": true,
		"sql_insert": true, "sql_update": true,
	}
	if !validFormats[opts.Format] {
		return nil, fmt.Errorf("formato no soportado: %s", opts.Format)
	}

	// Aplicar defaults
	if opts.Delimiter == "" {
		opts.Delimiter = ","
	}
	if opts.QuoteChar == "" {
		opts.QuoteChar = "\""
	}
	if opts.Encoding == "" {
		opts.Encoding = "utf-8"
	}
	if opts.LineEnding == "" {
		opts.LineEnding = "\n"
	}
	if opts.SheetName == "" {
		opts.SheetName = opts.TableName
	}
	if opts.IncludeHeader {
		opts.IncludeHeader = true
	}

	// Obtener datos
	data, err := em.fetchData(ctx, opts)
	if err != nil {
		return nil, err
	}

	startTime := time.Now()

	// Exportar según formato
	switch opts.Format {
	case "csv":
		err = em.exportCSV(w, data, opts)
	case "xlsx":
		err = em.exportExcel(w, data, opts)
	case "json":
		err = em.exportJSON(w, data, opts)
	case "sql_insert":
		err = em.exportSQLInsert(w, data, opts)
	case "sql_update":
		err = em.exportSQLUpdate(w, data, opts)
	}

	if err != nil {
		return nil, err
	}

	return &ExportResult{
		Format:    opts.Format,
		TableName: opts.TableName,
		RowCount:  len(data.Rows),
		Columns:   data.Columns,
		Duration:  time.Since(startTime),
	}, nil
}

// fetchData obtiene los datos a exportar
func (em *ExportManager) fetchData(ctx context.Context, opts ExportOptions) (*QueryResult, error) {
	tOpts := TableDataOptions{
		TableName: opts.TableName,
		Limit:     opts.Limit,
		Offset:    opts.Offset,
		Search:    opts.Search,
		SortBy:    opts.SortBy,
		SortDesc:  opts.SortDesc,
	}
	return em.client.GetTableData(ctx, tOpts)
}

// exportCSV exporta a CSV con opciones profesionales
func (em *ExportManager) exportCSV(w io.Writer, data *QueryResult, opts ExportOptions) error {
	// BOM para UTF-8 Excel-compatible
	if opts.Encoding == "utf-8-bom" {
		w.Write([]byte{0xEF, 0xBB, 0xBF})
	}

	// UTF-16 BOM
	if opts.Encoding == "utf-16" {
		w.Write([]byte{0xFF, 0xFE})
	}

	// Configurar writer
	sep := rune(opts.Delimiter[0])
	if opts.Delimiter == "\\t" {
		sep = '\t'
	}

	quoteChar := rune(opts.QuoteChar[0])

	// Header
	if opts.IncludeHeader {
		if opts.IncludeTypes {
			// Primera fila: nombres, segunda fila: tipos
			if err := em.writeCSVRow(w, data.Columns, sep, quoteChar); err != nil {
				return err
			}
			// Aquí podríamos agregar tipos si los tuviéramos
		} else {
			if err := em.writeCSVRow(w, data.Columns, sep, quoteChar); err != nil {
				return err
			}
		}
	}

	// Data rows
	for _, row := range data.Rows {
		strRow := make([]string, len(row))
		for i, val := range row {
			strRow[i] = formatValue(val)
		}
		if err := em.writeCSVRow(w, strRow, sep, quoteChar); err != nil {
			return err
		}
	}

	// Stats al final si se pide
	if opts.IncludeStats {
		fmt.Fprintf(w, "%s# Total rows: %d%s", opts.LineEnding, data.TotalRows, opts.LineEnding)
		fmt.Fprintf(w, "# Exported at: %s%s", time.Now().Format(time.RFC3339), opts.LineEnding)
	}

	return nil
}

// writeCSVRow escribe una fila CSV
func (em *ExportManager) writeCSVRow(w io.Writer, row []string, sep rune, quote rune) error {
	writer := csv.NewWriter(w)
	writer.Comma = sep

	if err := writer.Write(row); err != nil {
		return err
	}
	writer.Flush()
	return writer.Error()
}

// exportExcel exporta a Excel (.xlsx) con formato profesional
func (em *ExportManager) exportExcel(w io.Writer, data *QueryResult, opts ExportOptions) error {
	f := excelize.NewFile()
	defer f.Close()

	// Renombrar hoja
	sheetName := opts.SheetName
	if sheetName == "" {
		sheetName = "Data"
	}
	f.SetSheetName("Sheet1", sheetName)

	// Estilo para header
	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Bold:   opts.HeaderBold,
			Size:   11,
			Family: "Calibri",
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Pattern: 1, // solid
			Color:   []string{"#4472C4"},
		},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
		},
		Border: []excelize.Border{
			{Type: "left", Color: "000000", Style: 1},
			{Type: "right", Color: "000000", Style: 1},
			{Type: "top", Color: "000000", Style: 1},
			{Type: "bottom", Color: "000000", Style: 1},
		},
	})

	// Estilo para datos
	dataStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Size:   10,
			Family: "Calibri",
		},
		Border: []excelize.Border{
			{Type: "left", Color: "D9D9D9", Style: 1},
			{Type: "right", Color: "D9D9D9", Style: 1},
			{Type: "top", Color: "D9D9D9", Style: 1},
			{Type: "bottom", Color: "D9D9D9", Style: 1},
		},
	})

	// Estilo para alternar filas
	altStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Size:   10,
			Family: "Calibri",
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Pattern: 1, // solid
			Color:   []string{"#F2F2F2"},
		},
		Border: []excelize.Border{
			{Type: "left", Color: "D9D9D9", Style: 1},
			{Type: "right", Color: "D9D9D9", Style: 1},
			{Type: "top", Color: "D9D9D9", Style: 1},
			{Type: "bottom", Color: "D9D9D9", Style: 1},
		},
	})

	// Escribir headers
	if opts.IncludeHeader {
		for i, col := range data.Columns {
			cell, _ := excelize.CoordinatesToCellName(i+1, 1)
			f.SetCellValue(sheetName, cell, col)
			f.SetCellStyle(sheetName, cell, cell, headerStyle)
		}
	}

	// Escribir datos
	startRow := 1
	if opts.IncludeHeader {
		startRow = 2
	}

	for rowIdx, row := range data.Rows {
		for colIdx, val := range row {
			cell, _ := excelize.CoordinatesToCellName(colIdx+1, startRow+rowIdx)
			f.SetCellValue(sheetName, cell, formatValue(val))

			// Estilo alternado
			if rowIdx%2 == 0 {
				f.SetCellStyle(sheetName, cell, cell, dataStyle)
			} else {
				f.SetCellStyle(sheetName, cell, cell, altStyle)
			}
		}
	}

	// Auto-width si se pide
	if opts.AutoWidth {
		for i := range data.Columns {
			col, _ := excelize.ColumnNumberToName(i + 1)
			f.SetColWidth(sheetName, col, col, 20)
		}
	}

	// Freeze panes
	if opts.FreezePanes && opts.IncludeHeader {
		f.SetPanes(sheetName, &excelize.Panes{
			Freeze:      true,
			XSplit:      0,
			YSplit:      1,
			TopLeftCell: "A2",
			ActivePane:  "bottomLeft",
		})
	}

	// Metadata sheet si se pide
	if opts.IncludeStats || opts.IncludeTimestamp || opts.IncludeQuery {
		metaSheet := "Metadata"
		f.NewSheet(metaSheet)
		f.SetCellValue(metaSheet, "A1", "Export Info")
		f.SetCellValue(metaSheet, "A2", "Table")
		f.SetCellValue(metaSheet, "B2", opts.TableName)
		f.SetCellValue(metaSheet, "A3", "Format")
		f.SetCellValue(metaSheet, "B3", "Excel (xlsx)")
		f.SetCellValue(metaSheet, "A4", "Total Rows")
		f.SetCellValue(metaSheet, "B4", data.TotalRows)
		if opts.IncludeTimestamp {
			f.SetCellValue(metaSheet, "A5", "Exported At")
			f.SetCellValue(metaSheet, "B5", time.Now().Format(time.RFC3339))
		}
	}

	// Guardar
	return f.Write(w)
}

// exportJSON exporta a JSON con formato profesional
func (em *ExportManager) exportJSON(w io.Writer, data *QueryResult, opts ExportOptions) error {
	result := map[string]interface{}{
		"table":      opts.TableName,
		"columns":    data.Columns,
		"rows":       data.Rows,
		"total_rows": data.TotalRows,
	}

	if opts.IncludeTimestamp {
		result["exported_at"] = time.Now().Format(time.RFC3339)
	}

	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	return encoder.Encode(result)
}

// exportSQLInsert exporta como INSERT statements
func (em *ExportManager) exportSQLInsert(w io.Writer, data *QueryResult, opts ExportOptions) error {
	if opts.IncludeHeader {
		fmt.Fprintf(w, "-- Export de tabla: %s%s", opts.TableName, opts.LineEnding)
		fmt.Fprintf(w, "-- Fecha: %s%s", time.Now().Format(time.RFC3339), opts.LineEnding)
		fmt.Fprintf(w, "-- Total filas: %d%s%s", len(data.Rows), opts.LineEnding, opts.LineEnding)
	}

	// Batch de 100 inserts
	batchSize := 100
	for i := 0; i < len(data.Rows); i += batchSize {
		end := i + batchSize
		if end > len(data.Rows) {
			end = len(data.Rows)
		}
		batch := data.Rows[i:end]

		fmt.Fprintf(w, "INSERT INTO `%s` (`%s`) VALUES%s",
			opts.TableName,
			strings.Join(data.Columns, "`, `"),
			opts.LineEnding)

		for j, row := range batch {
			values := make([]string, len(row))
			for k, val := range row {
				values[k] = formatSQLValue(val)
			}
			sep := ","
			if j == len(batch)-1 {
				sep = ";"
			}
			fmt.Fprintf(w, "  (%s)%s", strings.Join(values, ", "), sep)
		}
		fmt.Fprint(w, opts.LineEnding)
	}

	return nil
}

// exportSQLUpdate exporta como UPDATE statements
func (em *ExportManager) exportSQLUpdate(w io.Writer, data *QueryResult, opts ExportOptions) error {
	if opts.IncludeHeader {
		fmt.Fprintf(w, "-- Export de tabla: %s%s", opts.TableName, opts.LineEnding)
		fmt.Fprintf(w, "-- Fecha: %s%s", time.Now().Format(time.RFC3339), opts.LineEnding)
	}

	// Necesitamos encontrar la primary key o usar la primera columna
	pkCol := data.Columns[0]

	for _, row := range data.Rows {
		setClauses := make([]string, len(data.Columns))
		for i, col := range data.Columns {
			setClauses[i] = fmt.Sprintf("`%s` = %s", col, formatSQLValue(row[i]))
		}

		fmt.Fprintf(w, "UPDATE `%s` SET %s WHERE `%s` = %s;%s",
			opts.TableName,
			strings.Join(setClauses, ", "),
			pkCol,
			formatSQLValue(row[0]),
			opts.LineEnding)
	}

	return nil
}

// formatValue formatea un valor para exportación
func formatValue(val interface{}) string {
	if val == nil {
		return "NULL"
	}
	switch v := val.(type) {
	case string:
		return v
	case []byte:
		return string(v)
	case time.Time:
		return v.Format(time.RFC3339)
	case bool:
		if v {
			return "true"
		}
		return "false"
	case float64, float32, int, int64, int32:
		return fmt.Sprintf("%v", v)
	default:
		return fmt.Sprintf("%v", v)
	}
}

// formatSQLValue formatea un valor para SQL
func formatSQLValue(val interface{}) string {
	if val == nil {
		return "NULL"
	}
	switch v := val.(type) {
	case string:
		escaped := strings.ReplaceAll(v, "'", "''")
		return fmt.Sprintf("'%s'", escaped)
	case []byte:
		escaped := strings.ReplaceAll(string(v), "'", "''")
		return fmt.Sprintf("'%s'", escaped)
	case time.Time:
		return fmt.Sprintf("'%s'", v.Format("2006-01-02 15:04:05"))
	case bool:
		if v {
			return "TRUE"
		}
		return "FALSE"
	case float64, float32, int, int64, int32:
		return fmt.Sprintf("%v", v)
	default:
		escaped := strings.ReplaceAll(fmt.Sprintf("%v", v), "'", "''")
		return fmt.Sprintf("'%s'", escaped)
	}
}

// ExportResult resultado de la exportación
type ExportResult struct {
	Format    string        `json:"format"`
	TableName string        `json:"table_name"`
	RowCount  int           `json:"row_count"`
	Columns   []string      `json:"columns"`
	Duration  time.Duration `json:"duration"`
}
