# DBOtter 
#### Interfaz nativa de Apple (SwiftUI) que no consume recursos, impulsada por un motor de datos ultraligero y eficiente (Go). Es el matrimonio perfecto: la elegancia de Apple con la fuerza bruta de Google.


<!-- <table> -->
<img src="./uploads/main.png" width="300" alt="Vista principal">
<img src="./uploads/diagram.png" width="300" alt="Vista de diagrama ER">
<img src="./uploads/sql.png" width="300" alt="Vista para ejecutar query SQL">
<img src="./uploads/connection.png" width="300" alt="Vista de formulario de nueva conexión">

<!-- </table> -->

### PARA COMPILAR CORE GO
- MacOS: GOOS=darwin GOARCH=arm64 go build -o core-engine main.go

##### Proyecto abierto para nuevas integraciones con otros Sistemas operativos, consumiendo solo el core-engine. Y para mejorar y agregar nuevos motores de base de datos en el futuro