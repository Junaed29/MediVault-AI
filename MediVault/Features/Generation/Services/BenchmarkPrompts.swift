//
//  BenchmarkPrompts.swift
//  MediVault
//
//  Created by Junaed Chowdhury on 28/1/26.
//

import Foundation

enum BenchmarkPrompts {
    static let cases: [(label: String, context: String, query: String)] = [
        (
            label: "short-lookup",
            context: "Patient: John Doe. Visit Date: 2024-01-15. Blood Pressure: 120/80 mmHg. Heart Rate: 72 bpm. Physician: Dr. Smith.",
            query: "What was my blood pressure?"
        ),
        (
            label: "multi-value",
            context: "Lab Results (2024-03-10): Hemoglobin 14.2 g/dL. Glucose 95 mg/dL. Cholesterol 180 mg/dL. LDL 110 mg/dL. HDL 55 mg/dL.",
            query: "Summarize my lab results."
        ),
        (
            label: "medication-list",
            context: "Prescribed 2024-02-01: Metformin 500mg twice daily. Lisinopril 10mg once daily. Atorvastatin 20mg at bedtime.",
            query: "What medications am I taking and how often?"
        ),
        (
            label: "date-filter",
            context: "Visits: 2023-09-01 routine checkup. 2023-12-15 flu. 2024-01-15 follow-up. 2024-03-10 labs.",
            query: "What visits did I have in 2024?"
        ),
        (
            label: "long-synthesis",
            context: """
            Visit 2024-01-15 Dr. Smith: BP 120/80, HR 72, weight 75kg. Prescribed Metformin 500mg.
            Visit 2024-02-20 Dr. Patel: BP 125/82, fasting glucose 105 mg/dL. Continued Metformin.
            Visit 2024-03-10 Dr. Smith: BP 118/78, HbA1c 6.1%. Reduced Metformin to 250mg.
            """,
            query: "How has my blood pressure and diabetes management changed over these three visits?"
        ),
    ]
}
