// RawFolder parameter = "D:\\claude life\\01_Projects\\04_Telecom_Churn\\01_Raw_Data\\"
let
    Source = Csv.Document(File.Contents(RawFolder & "telecom_customer_churn.csv"), [Delimiter = ",", Columns = 38, Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    BlanksToNull = Table.ReplaceValue(Promoted, "", null, Replacer.ReplaceValue, Table.ColumnNames(Promoted)),
    // Rule 1: data types (en-US numbers)
    Typed = Table.TransformColumnTypes(BlanksToNull, {
        {"Customer ID", type text}, {"Gender", type text}, {"Age", Int64.Type}, {"Married", type text}, {"Number of Dependents", Int64.Type},
        {"City", type text}, {"Zip Code", type text}, {"Number of Referrals", Int64.Type}, {"Tenure in Months", Int64.Type},
        {"Avg Monthly Long Distance Charges", type number}, {"Avg Monthly GB Download", Int64.Type}, {"Monthly Charge", type number},
        {"Total Charges", type number}, {"Total Refunds", type number}, {"Total Extra Data Charges", type number},
        {"Total Long Distance Charges", type number}, {"Total Revenue", type number}}, "en-US"),
    // Rule 2: structural blanks -> labels (no internet / no phone / no offer)
    NoInternet = Table.TransformColumns(Typed, List.Transform({"Internet Type", "Online Security", "Online Backup", "Device Protection Plan", "Premium Tech Support", "Streaming TV", "Streaming Movies", "Streaming Music", "Unlimited Data"}, (c) => {c, each if _ = null then "No Internet" else _, type text})),
    NoPhone = Table.TransformColumns(NoInternet, {{"Multiple Lines", each if _ = null then "No Phone" else _, type text}}),
    NoOffer = Table.TransformColumns(NoPhone, {{"Offer", each if _ = null or _ = "None" then "No Offer" else _, type text}}),
    // Rule 3: churn category / reason blank = not churned
    NotChurned = Table.TransformColumns(NoOffer, {{"Churn Category", each if _ = null then "Not Churned" else _, type text}, {"Churn Reason", each if _ = null then "Not Churned" else _, type text}}),
    // Rule 4: 120 negative monthly charges -> positive (Ahmed's decision) + flag
    AddNegFlag = Table.AddColumn(NotChurned, "Charge Was Negative", each if [Monthly Charge] < 0 then 1 else 0, Int64.Type),
    AbsCharge = Table.TransformColumns(AddNegFlag, {{"Monthly Charge", Number.Abs, type number}}),
    // Rule 5: flags
    AddChurned = Table.AddColumn(AbsCharge, "Is Churned", each if [Customer Status] = "Churned" then 1 else 0, Int64.Type),
    AddBase = Table.AddColumn(AddChurned, "In Churn Base", each if [Customer Status] = "Joined" then 0 else 1, Int64.Type),
    // Rule 6: bands
    AddAge = Table.AddColumn(AddBase, "Age Group", each if [Age] < 30 then "19-29" else if [Age] < 40 then "30-39" else if [Age] < 50 then "40-49" else if [Age] < 60 then "50-59" else if [Age] < 70 then "60-69" else "70+", type text),
    AddAgeOrder = Table.AddColumn(AddAge, "Age Group Order", each if [Age] < 30 then 1 else if [Age] < 40 then 2 else if [Age] < 50 then 3 else if [Age] < 60 then 4 else if [Age] < 70 then 5 else 6, Int64.Type),
    AddTenure = Table.AddColumn(AddAgeOrder, "Tenure Band", each if [Tenure in Months] <= 6 then "0-6 mo" else if [Tenure in Months] <= 12 then "7-12 mo" else if [Tenure in Months] <= 24 then "13-24 mo" else if [Tenure in Months] <= 48 then "25-48 mo" else "49-72 mo", type text),
    AddTenureOrder = Table.AddColumn(AddTenure, "Tenure Band Order", each if [Tenure in Months] <= 6 then 1 else if [Tenure in Months] <= 12 then 2 else if [Tenure in Months] <= 24 then 3 else if [Tenure in Months] <= 48 then 4 else 5, Int64.Type),
    AddCharge = Table.AddColumn(AddTenureOrder, "Charge Band", each if [Monthly Charge] < 30 then "$0-29" else if [Monthly Charge] < 60 then "$30-59" else if [Monthly Charge] < 90 then "$60-89" else "$90+", type text),
    AddChargeOrder = Table.AddColumn(AddCharge, "Charge Band Order", each if [Monthly Charge] < 30 then 1 else if [Monthly Charge] < 60 then 2 else if [Monthly Charge] < 90 then 3 else 4, Int64.Type),
    // Rule 7: number of add-on services (Yes answers)
    AddServices = Table.AddColumn(AddChargeOrder, "Add-on Services", each List.Count(List.Select({[Online Security], [Online Backup], [Device Protection Plan], [Premium Tech Support], [Streaming TV], [Streaming Movies], [Streaming Music], [Unlimited Data]}, (x) => x = "Yes")), Int64.Type),
    AddReferral = Table.AddColumn(AddServices, "Referral Status", each if [Number of Referrals] > 0 then "Referred friends" else "No referrals", type text),
    AddDependents = Table.AddColumn(AddReferral, "Has Dependents", each if [Number of Dependents] > 0 then "Yes" else "No", type text),
    // Rule 8: value segment = quartile of Total Revenue
    Sorted = List.Buffer(List.Sort(AddDependents[Total Revenue])),
    N = List.Count(Sorted),
    Q1 = Sorted{Number.RoundDown(0.25 * (N - 1))}, Q2 = Sorted{Number.RoundDown(0.5 * (N - 1))}, Q3 = Sorted{Number.RoundDown(0.75 * (N - 1))},
    AddSegment = Table.AddColumn(AddDependents, "Value Segment", each if [Total Revenue] > Q3 then "Top 25%" else if [Total Revenue] > Q2 then "Upper-mid 25%" else if [Total Revenue] > Q1 then "Lower-mid 25%" else "Bottom 25%", type text),
    AddSegmentOrder = Table.AddColumn(AddSegment, "Value Segment Order", each if [Total Revenue] > Q3 then 1 else if [Total Revenue] > Q2 then 2 else if [Total Revenue] > Q1 then 3 else 4, Int64.Type),
    // Rule 9: location columns live in the Locations dimension
    Removed = Table.RemoveColumns(AddSegmentOrder, {"City", "Latitude", "Longitude"}),
    // Rule 10: final types (set last; earlier replace steps can drop types)
    FinalTypes = Table.TransformColumnTypes(Removed, {{"Monthly Charge", Currency.Type}, {"Total Charges", Currency.Type}, {"Total Refunds", Currency.Type}, {"Total Extra Data Charges", Currency.Type}, {"Total Long Distance Charges", Currency.Type}, {"Total Revenue", Currency.Type}, {"Avg Monthly Long Distance Charges", Currency.Type}, {"Zip Code", type text}})
in
    FinalTypes
