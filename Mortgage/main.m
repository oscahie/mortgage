//
//  main.m
//  Mortgage
//
//  Created by Oscar Hierro on 28/06/15.
//  Copyright (c) 2015 Oscar Hierro. All rights reserved.
//

#import <Foundation/Foundation.h>

#define NSLog(FORMAT, ...) printf("%s\n", [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);

typedef enum {
    MortgageTypeLinear,
    MortgageTypeAnnuitity
}
MortgageType;

// declarations
void calculateMortgage(MortgageType mortgageType);
double calculateMonthlyPayment(double totalMortgageAmount, int totalMonths, double interestRatePercentage);
double calculateInterestRate(double totalMortgageAmount, double monthlyPayment, int totalMonths);


int main(int argc, const char * argv[]) {
    @autoreleasepool
    {
        //calculateMortgage(MortgageTypeAnnuitity);
        calculateMortgage(MortgageTypeLinear);
    }
    return 0;
}

/* Some custom options for adjustments that can be made during the lifetime of the loan */

#define EXPIRING_30_PERCENT_RULING          1
#define ADJUST_LOAN_RISKCLASS               1
#define ADJUST_PRINCIPAL_REPAYMENT_YEARLY   1

void calculateMortgage(MortgageType mortgageType)
{
    /* INPUT DATA */
    
    // basic parameters
    double totalMortgageAmount = 240000;    // the total loaned amount €
    int mortgagePeriodYears = 30;           // the mortgage's repayment period (in years)
    double nominalInterestRate = 0.0234;    // the mortgage's nominal interest rate (eg. 0.029 = 2.9%) (assumed fixed for the entire period)
    double annualRepayment = 20000;         // an extra amount (in €) that is planned to be repaid once per year, every year, on the last month
    double mortgageArrangementFee = 1250;   // the total amount paid as arrangement fees
    
    // dutch mortgage tax relief
    double maxDeductionRateCurrentYear = 0.505; // 51% in 2015, decreasing 0.5% per year until 2038, when it has reached 38%
    double incomeTaxBracket = 0.52;          // the highest taxation bracket applied to your salary (eg: 0.52 = 52%)
    int initialYear = 2016;

    // the WOZ values of the property (in €) on January 1st, starting at the year before the purchase year
    // years in the future for which the WOZ is not yet known will use the most recent available value
    NSDictionary<NSNumber *, NSNumber*> *WOZPerYear = @{@(2015): @(270500),
                                                        @(2016): @(285000),
                                                        @(2017): @(382000)};
    
    /**************/
    
    int mortgagePeriodMonths = mortgagePeriodYears * 12;
    double remainingDebt = totalMortgageAmount;
    double monthlyInterestRate = nominalInterestRate / 12;
    double monthlyPayment;
    
    if (mortgageType == MortgageTypeLinear)
    {
        // for a linear mortgage this amount will be the principal paid each month
        monthlyPayment = totalMortgageAmount / (mortgagePeriodMonths);
    }
    else /* (mortgageType == MortgageTypeAnnuitity) */
    {
        // the annuity formula provides the gross fee paid each month, including principal and interest
        monthlyPayment = totalMortgageAmount * monthlyInterestRate / (1 - (pow(1/(1 + monthlyInterestRate), mortgagePeriodMonths)));
    }
    
    NSLog(@">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>");
    NSLog(@">>> %@ Mortgage <<<", mortgageType == MortgageTypeAnnuitity ? @"Annuity" : @"Linear");
    NSLog(@"> Mortgage details: €%.0f at %.2f%% during %lu years", totalMortgageAmount, nominalInterestRate*100, (unsigned long)mortgagePeriodYears);
    NSLog(@"> Additional annual repayment: €%.0f", annualRepayment);
    
    double totalPaid = 0;
    double totalInterestPaid = 0;
    double totalNetPaid = 0; // with tax relief
    double totalNetInterestPaid = 0;
    int totalPeriodMonths = 0;
    int yearCount = 0;
    BOOL stillInDebt = YES;
    
    // The applicable WOZ value for a given year is the value on 1st of January of the previous year
    double applicableWOZValue = WOZPerYear[@(initialYear - 1)].doubleValue;
    NSCAssert(applicableWOZValue > 0, @"WOZ value not available for the first year");
    
    for (int year = initialYear; year <= initialYear + mortgagePeriodYears && stillInDebt; year++)
    {
        NSLog(@"\n*********** Year %d (#%d) - Remaining debt: €%.0f ***********", year, yearCount + 1, remainingDebt);
        
#if EXPIRING_30_PERCENT_RULING
        /* custom code to deal with the 30% ruling expiring in 2018, after which the income tax bracket becomes 52% instead of 42% */
        if (year <= 2018)
        {
            incomeTaxBracket = 0.42;
        }
        else
        {
            incomeTaxBracket = 0.52;
        }
#endif
        
#if ADJUST_LOAN_RISKCLASS
        /* adjust the loan's risk class from initial 85% to 65% on the third year, thanks to downpayments and revalorization of the property */
        if (year >= 2018)
        {
            nominalInterestRate = 0.0214; // Hypotrust Comfort (standaard), 10 years, t/m 65%, 1.87% in december 2015
            monthlyInterestRate = nominalInterestRate / 12;
        }
#endif
        double taxDeductionRate = MIN(maxDeductionRateCurrentYear, incomeTaxBracket);
        double totalInterestPaidThisYear = 0;
        double totalNetInterestPaidThisYear = 0;
        double principalAmmortizedThisYear = 0;
        
        // if we have a WOZ value for the previous year then use it, otherwise reuse the last known value from a previous iteration
        if (WOZPerYear[@(year - 1)])
        {
            applicableWOZValue = WOZPerYear[@(year - 1)].doubleValue;
        }
        
        // Deemed rental value (eigenwoningforfait)
        // In 2016 and 2017 it was 0.75% of WOZ value
        // In 2018 it was 0.70%
        double monthlyEWF =  (applicableWOZValue * (year < 2018 ? 0.0075 : 0.007)) / 12;
        
        for (int month = 1; month <= 12 && stillInDebt; month++)
        {
            if (remainingDebt <= 1)
            {
                stillInDebt = NO;
                continue;
            }
            
            // can we finish off the loan now with one single payment? then do so in order to avoid paying interest over the remaining months
            if (annualRepayment > 0 && remainingDebt <= annualRepayment)
            {
                double amountAmortized = MIN(annualRepayment, remainingDebt);
                
                NSLog(@" + final repayment: €%.0f", amountAmortized);
                remainingDebt -= amountAmortized;
                totalPaid += amountAmortized;
                totalNetPaid += amountAmortized;
                principalAmmortizedThisYear += amountAmortized;
                
                stillInDebt = NO;
                continue;
            }
            
            double interestPaidThisMonth = monthlyInterestRate * remainingDebt;
            double principalPaidThisMonth;
            
            if (mortgageType == MortgageTypeLinear)
            {
                principalPaidThisMonth = monthlyPayment;
            }
            else /* (mortgageType == MortgageTypeAnnuitity) */
            {
                // in this case the calculated monthly payment is the gross amount, including interest and principal
                principalPaidThisMonth = monthlyPayment - interestPaidThisMonth;
            }
            
            double grossMortgagePremiumThisMonth = interestPaidThisMonth + principalPaidThisMonth;
            
            // the eigenwoningforfait is a kind of compensation for the enjoyment of your own home, so it counts as a fictitious income and thus is taxable in Box 1
            double additionalTaxableIncome = monthlyEWF;
            
            // TODO: consider deducting also the ground lease fee (erfpacht)
            
            // tax deduction over mortgage interest paid (up to 30 years max)
            double taxBenefitsThisMonth = 0;
            
            if (interestPaidThisMonth > additionalTaxableIncome && year <=  initialYear + 30)
            {
                taxBenefitsThisMonth = (interestPaidThisMonth - monthlyEWF) * taxDeductionRate;
            }
            
            // the net mortgage fee paid this month
            double netMortgagePremiumThisMonth = grossMortgagePremiumThisMonth - taxBenefitsThisMonth;
            
            NSLog(@" month %d --> interest = €%.2f, principal = €%.2f, gross total = €%.2f, tax benefit = €%.2f, net total = €%.2f", month, interestPaidThisMonth, principalPaidThisMonth, grossMortgagePremiumThisMonth, taxBenefitsThisMonth, netMortgagePremiumThisMonth);
            
            totalPaid += grossMortgagePremiumThisMonth;
            totalInterestPaid += interestPaidThisMonth;
            totalInterestPaidThisYear += interestPaidThisMonth;
            totalNetPaid += netMortgagePremiumThisMonth;
            totalNetInterestPaid += interestPaidThisMonth - taxBenefitsThisMonth;
            totalNetInterestPaidThisYear += interestPaidThisMonth - taxBenefitsThisMonth;
            remainingDebt -= principalPaidThisMonth;
            principalAmmortizedThisYear += principalPaidThisMonth;
            totalPeriodMonths++;
        }
        
        // extra amortizations once per year
        // note: potential early payment pennalties are not considered here
        if (annualRepayment > 0 && remainingDebt > 0)
        {
            double amountAmortized = MIN(annualRepayment, remainingDebt);
            
            NSLog(@" + extra annual repayment: €%.0f", amountAmortized);
            remainingDebt -= amountAmortized;
            totalPaid += amountAmortized;
            totalNetPaid += amountAmortized;
            principalAmmortizedThisYear += amountAmortized;
            
            if (remainingDebt <= 1)
            {
                stillInDebt = NO;
            }
            
#if ADJUST_PRINCIPAL_REPAYMENT_YEARLY
            // adjust the monthly principal ammount to the new mortgate total (weird, but this is what Hypotrust seems to do!)
            monthlyPayment = remainingDebt / (mortgagePeriodMonths);
#endif
        }
        
        NSLog(@" * interest paid: €%.0f (with tax benefits: €%.0f)", totalInterestPaidThisYear, totalNetInterestPaidThisYear);
        NSLog(@" * total tax benefits: €%.0f", totalInterestPaidThisYear - totalNetInterestPaidThisYear);
        NSLog(@" * total ammortized: €%.0f", principalAmmortizedThisYear);
        
        // tax relief decreases by 0.5% per year and it's capped at 38% (for now, at least)
        if (maxDeductionRateCurrentYear > 0.38)
        {
            maxDeductionRateCurrentYear -= 0.005;
        }
        
        yearCount++;
    }
    
    NSLog(@"\n*******************************************************\n");
    NSLog(@">>> Mortgage paid in full in %i year(s) and %i month(s)!\n", totalPeriodMonths / 12, totalPeriodMonths % 12);

    NSLog(@"Total net amount paid: €%.0f", totalNetPaid);
    NSLog(@"Total net interest paid: €%.0f", totalNetInterestPaid);
    NSLog(@"Final interest to loan ratio: %.0f%%", totalNetInterestPaid * 100/totalMortgageAmount);
    //NSLog(@"Total tax benefits: €%.0f", totalInterestPaid - totalNetInterestPaid);
    
    
    // calculate the effective interest rate
    // It is slightly higher than the borrowing rate because it takes into account that you pay your mortgage every month in arrears.
    //    r_eff = (1+r/n)^n-1
    //    r -> nominal interest rate
    //    n -> compounding periods
    
    double effectiveInterestRate = pow(1 + nominalInterestRate/mortgagePeriodMonths, mortgagePeriodMonths) - 1;
    NSLog(@"Effective interest rate: %.2f%% (+%.2f%%)", effectiveInterestRate * 100, (effectiveInterestRate - nominalInterestRate) * 100);
    
    // Annual Percentage Rate (APR) is the equivalent interest rate considering all the added costs (arrangement fees) to a given loan
    // http://www.efunda.com/formulae/finance/apr_calculator.cfm
    
    // calculate the fixed monthly fee for the total mortgage amount, ignoring the costs
    double monthlyRate = calculateMonthlyPayment(totalMortgageAmount, mortgagePeriodMonths, nominalInterestRate * 100);
    
    // then approximate the interest rate that would correspond to such monthly fee when the loan costs have been factored in
    double APR = calculateInterestRate(totalMortgageAmount - mortgageArrangementFee, monthlyRate, mortgagePeriodMonths);
    
    NSLog(@"Annual Percentage Rate: %.2f%% (+%.2f%%)", APR, APR - nominalInterestRate * 100);
}

/*
 Calculates the monthly payment for the given loan amount, period and interest rate using the annuity formula
 */
double calculateMonthlyPayment(double totalMortgageAmount, int totalMonths, double interestRatePercentage)
{
    double interestRateMonthlyDec = interestRatePercentage / 1200;
    
    return totalMortgageAmount * (interestRateMonthlyDec / (1 - pow(1 + interestRateMonthlyDec, -1 * totalMonths)));
}

/*
 Calculates the (approximated) interest rate figure that would correspond to the given loan amount, monthly fee and period
 
 http://www.hughcalc.org/formula.php
 */
double calculateInterestRate(double totalMortgageAmount, double monthlyPayment, int totalMonths)
{
    double minInterestRate = 0;
    double maxInterestRate = 100;
    double interestRate = 0;
    
    while (minInterestRate < maxInterestRate - 0.0001)
    {
        // try the middle rate
        interestRate = (minInterestRate + maxInterestRate) / 2;
        
        double guessedMonthlyPayment = calculateMonthlyPayment(totalMortgageAmount, totalMonths, interestRate);
        
        if (guessedMonthlyPayment > monthlyPayment)
        {
            maxInterestRate = interestRate; // current rate is new maximum
        }
        else
        {
            minInterestRate = interestRate; // current rate is new minimum
        }
    }
    
    return interestRate; // in percentage
}


