import json

# Actual registrations from live DB
live_regs = [5000, 5004, 5005, 5062, 5075, 5081, 5085, 5089, 5090, 5092, 5093, 5094, 5096, 5097, 5098, 5099, 5100, 5101, 5104, 5105, 5107, 5108, 5109, 5111, 5112, 5113, 5114, 5117, 5118, 5121, 5124, 5125, 5126, 5128, 5130, 5131, 5132, 5133, 5134, 5135, 5136, 5137, 5138, 5139, 5140, 5141, 5142, 5143, 5144, 5145, 5146, 5147, 5148, 5149, 5150, 5152, 5153, 5154, 5155, 5156, 5157, 5158, 5161, 5162, 5163, 5165, 5166, 5168, 5169, 5170, 5171, 5172, 5173, 5174, 5177, 5178, 5180, 5181, 5182, 5183, 5184, 5185, 5186, 5187, 5188, 5189, 5190, 5191, 5192, 5193, 5194, 5195, 5196, 5197, 5198, 5199, 5200, 5201, 5202, 5204, 5205, 5206, 5207, 5208, 5209, 5210, 5211, 5212, 5213, 5214, 5215, 5216, 5217, 5218, 5219, 5220, 5221, 5222, 5223, 5224, 5225, 5226, 8959]

# Fixture from export (ending at 5217 + 8959)
export_regs = [x for x in live_regs if x <= 5217 or x == 8959]

def determine_sequence_tail(numbers, max_gap_threshold=100):
    """
    Given a list of numeric registration numbers:
    1. Filter positive numbers and sort ascending.
    2. Identify isolated outliers: numbers separated by a gap > max_gap_threshold
       from the previous number where the cluster size above the gap is small (outlier).
    3. Return (established_tail, outliers).
    """
    if not numbers:
        return 0, []
    
    unique_sorted = sorted(list(set(n for n in numbers if n is not None and n > 0)))
    if not unique_sorted:
        return 0, []
    
    # If all numbers are within reasonable gaps:
    # Walk from the highest number downward. If the gap to previous number is > max_gap_threshold,
    # and the number of elements above the gap is small (< 5% of total or <= 3), they are outliers!
    outliers = []
    tail = unique_sorted[-1]
    
    for i in range(len(unique_sorted) - 1, 0, -1):
        curr = unique_sorted[i]
        prev = unique_sorted[i - 1]
        gap = curr - prev
        elements_above = len(unique_sorted) - i
        
        if gap > max_gap_threshold and elements_above <= max(3, len(unique_sorted) * 0.05):
            outliers.extend(unique_sorted[i:])
            tail = prev
            break
            
    return tail, sorted(outliers)

tail_export, outliers_export = determine_sequence_tail(export_regs)
print(f"Export fixture: tail = {tail_export}, next = {tail_export + 1}, outliers = {outliers_export}")

tail_live, outliers_live = determine_sequence_tail(live_regs)
print(f"Live database:  tail = {tail_live}, next = {tail_live + 1}, outliers = {outliers_live}")
