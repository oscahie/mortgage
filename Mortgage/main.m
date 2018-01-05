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


void calculateMortgage(MortgageType mortgageType)
{
    /* INPUT DATA */
    
    // basic parameters
    double totalMortgageAmount = 240000;    // the total loaned amount €
    int mortgagePeriodYears = 30;           // the mortgage's repayment period (in years)
    double nominalInterestRate = 0.0234;    // the mortgage's nominal interest rate (eg. 0.029 = 2.9%) (assumed fixed for the entire period)
    double annualAmortization = 20000;          // the amount (in €) that is planned to be amortized once per year
    double mortgageArrangementFee = 1250;   // the total amount paid as arrangement fees
    
    // dutch mortgage tax relief
    double WOZValueOfProperty = 255000;     // the WOZ value of the property (in €)
    double maxDeductionRateCurrentYear = 0.505; // 51% in 2015, decreasing 0.5% per year until 2038, when it has reached 38%
    double incomeTaxBracket = 0.52;          // the highest taxation bracket applied to your salary (eg: 0.52 = 52%)
    
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
    
    // Deemed rental value (eigenwoningforfait)
    // In 2015 it's 0.75% of WOZ value
    double monthlyEWF = (WOZValueOfProperty * 0.0075) / 12;
    
    NSLog(@">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>");
    NSLog(@">>> %@ Mortgage <<<", mortgageType == MortgageTypeAnnuitity ? @"Annuity" : @"Linear");
    NSLog(@"> Mortgage details: €%.0f at %.2f%% during %lu years", totalMortgageAmount, nominalInterestRate*100, (unsigned long)mortgagePeriodYears);
    NSLog(@"> WOZ value: €%.0f", WOZValueOfProperty);
    NSLog(@"> Eigenwoningforfait: €%.2f/month", monthlyEWF);
    NSLog(@"> Annual amortization: €%.0f", annualAmortization);
    
    double totalPaid = 0;
    double totalInterestPaid = 0;
    double totalNetPaid = 0; // with tax relief
    double totalNetInterestPaid = 0;
    int totalPeriodMonths = 0;
    BOOL stillInDebt = YES;
    
    for (int year = 1; year <= mortgagePeriodYears && stillInDebt; year++)
    {
        NSLog(@"*********** Year %d - Remaining debt: €%.0f ***********", year, remainingDebt);
        
#if 1
        /* custom code to deal with the 30% ruling expiring after 3 years, after which the income tax bracket becomes 52% instead of 42% */
        if (year <= 3)
        {
            incomeTaxBracket = 0.42;
        }
        else
        {
            incomeTaxBracket = 0.52;
        }
#endif
        double taxDeductionRate = MIN(maxDeductionRateCurrentYear, incomeTaxBracket);
        
        for (int month = 1; month <= 12 && stillInDebt; month++)
        {
            if (remainingDebt <= 1)
            {
                stillInDebt = NO;
                break;
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
            
            if (interestPaidThisMonth > additionalTaxableIncome && year <= 30)
            {
                taxBenefitsThisMonth = (interestPaidThisMonth - monthlyEWF) * taxDeductionRate;
            }
            
            // the net mortgage fee paid this month
            double netMortgagePremiumThisMonth = grossMortgagePremiumThisMonth - taxBenefitsThisMonth;
            
            NSLog(@" month %d --> interest = €%.2f, principal = €%.2f, gross total = €%.2f, tax benefit = €%.2f, net total = €%.2f", month, interestPaidThisMonth, principalPaidThisMonth, grossMortgagePremiumThisMonth, taxBenefitsThisMonth, netMortgagePremiumThisMonth);
            
            totalPaid += grossMortgagePremiumThisMonth;
            totalInterestPaid += interestPaidThisMonth;
            totalNetPaid += netMortgagePremiumThisMonth;
            totalNetInterestPaid += interestPaidThisMonth - taxBenefitsThisMonth;
            remainingDebt -= principalPaidThisMonth;
            totalPeriodMonths++;
        }
        
        // extra amortizations once per year
        // note: potential early payment pennalties are not considered here
        if (annualAmortization > 0 && remainingDebt > 0)
        {
            double amountAmortized = MIN(annualAmortization, remainingDebt);
            
            NSLog(@" + annual amortization: €%.0f", amountAmortized);
            remainingDebt -= amountAmortized;
            totalPaid += amountAmortized;
            totalNetPaid += amountAmortized;
        }
        
        // tax relief decreases by 0.5% per year and it's capped at 38% (for now, at least)
        if (maxDeductionRateCurrentYear > 0.38)
        {
            maxDeductionRateCurrentYear -= 0.005;
        }
    }
    
    NSLog(@"*******************************************************");
    NSLog(@">>> Mortgage paid in full in %i year(s) and %i month(s)!", totalPeriodMonths / 12, totalPeriodMonths % 12);

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


