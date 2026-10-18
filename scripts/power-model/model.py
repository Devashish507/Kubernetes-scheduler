import csv
import sys

# Power profiles obtained from cluster node labels
PROFILES = {
    "efficient": {"p_idle": 20, "p_max": 60},
    "medium": {"p_idle": 40, "p_max": 120},
    "power-hungry": {"p_idle": 80, "p_max": 200},
}

def calculate_power(p_idle, p_max, utilization_percent):
    """
    Calculate estimated power based on a linear model.
    P(u) = P_idle + (P_max - P_idle) * (u / 100)
    """
    u = utilization_percent / 100.0
    return p_idle + (p_max - p_idle) * u

def main():
    utilizations = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    output_file = "scripts/power-model/sample-data.csv"

    with open(output_file, mode="w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["profile", "utilization_percent", "idle_power_w", "max_power_w", "calculated_power_w"])

        for profile_name, data in PROFILES.items():
            for util in utilizations:
                p = calculate_power(data["p_idle"], data["p_max"], util)
                writer.writerow([
                    profile_name,
                    util,
                    data["p_idle"],
                    data["p_max"],
                    f"{p:.2f}"
                ])
                print(f"Profile: {profile_name:15} Util: {util:>3}% -> Power: {p:.2f}W")

    print(f"\nSuccessfully generated sample data at {output_file}")

if __name__ == "__main__":
    main()
