# Role: Senior Full-Stack Engineer & AI Data Architect

# Context
I am building a high-end Retail Intelligence Engine for "Allen Solly" (an ABFR brand). 
The goal is to input raw XML Tlogs (ARTS POSLog standard) and output a structured MongoDB 
document enriched with an "AI Intelligence Layer" that provides interactive, actionable insights.

# Task 1: Data Infrastructure & Parsing
1. Create a Node.js/TypeScript script that watches an `/inputs` folder for XML files.
2. Use a robust parser (like `fast-xml-parser`) to handle the ARTS POSLog v6.0 schema.
3. Define a Mongoose Schema for MongoDB that captures:
   - Header: StoreID, TerminalID, TransactionID, Timestamp.
   - Line Items: ItemID, Description, Size, Fit, Quantity, Price, and GST (CGST/SGST).
   - Totals: SubTotal, GrandTotal, TaxTotal, Rounding.
   - Loyalty: CustomerID, PointsEarned.
4. Ensure all currency fields are stored as `Decimal128` and dates as `ISODate`.

# Task 2: AI Intelligence Layer (Enrichment)
Integrate an LLM (using OpenAI or Anthropic API) to process each transaction. 
For every incoming Tlog, generate an `ai_insights` object to be stored in the document:
- **customer_persona**: Inferred based on basket composition (e.g., 'Formal Professional', 'Casual Weekender').
- **smart_cross_sell**: One specific item they should be targeted with next (e.g., "Brown Leather Belt" if they bought "Navy Chinos").
- **anomaly_flag**: Detect if the discount percentage or transaction flow looks suspicious.
- **inventory_urgency**: A flag (1-5) on how quickly this specific SKU needs replenishment based on the quantity sold.

# Task 3: Interactive Insights Output
Create a CLI-based or simple Web-based "Intelligence Dashboard" output that does the following:
1. **Real-time Feed**: Log every transaction processed with its AI Persona and Cross-sell suggestion.
2. **Aggregated Intelligence**: Provide a summary function that queries MongoDB to show:
   - "Top 3 Personas shopping today."
   - "Projected GST liability for the current batch."
   - "Potential revenue lost" (based on items that were discounted).

# Execution Guidelines
- Use `@` to reference my local files if I provide the XML sample.
- Follow Clean Architecture: separate the `parser`, `database`, and `ai_service`.
- Implement error handling for malformed XML and API timeouts.
- DO NOT use placeholders; write the full implementation logic.

# Interactive Step
Once the code is generated, show me how to run a query to find: 
"Which customer persona contributed the most to the CGST collection today?"